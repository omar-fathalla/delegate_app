import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:delegate_app/core/widgets/app_snack_bar.dart';
import 'package:delegate_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

import '../../../../l10n/app_localizations.dart';

/// صفحة الملف الشخصي للمستخدم
/// User Profile Screen with ability to change password and photo
class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({super.key});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final _auth = FirebaseAuth.instance;
  User? _currentUser;
  bool _isLoading = true;
  bool _isUploadingPhoto = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    setState(() {
      _currentUser = _auth.currentUser;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: colorScheme.surface,
        appBar: AppBar(
          title: Text(l10n.profile),
          backgroundColor: colorScheme.surface,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_currentUser == null) {
      return Scaffold(
        backgroundColor: colorScheme.surface,
        appBar: AppBar(
          title: Text(l10n.profile),
          backgroundColor: colorScheme.surface,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: colorScheme.error),
              const SizedBox(height: 16),
              Text(
                'لم يتم العثور على المستخدم',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colorScheme.error,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(l10n.profile),
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      body: BlocBuilder<AuthBloc, AuthState>(
        builder: (context, state) {
          Delegate? delegate;
          if (state is AuthAuthenticated) {
            delegate = state.delegate;
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Profile Header
                _buildProfileHeader(colorScheme, theme, delegate),

                const SizedBox(height: 24),

                // Personal Information Card
                _buildPersonalInfoCard(colorScheme, theme, l10n, delegate),

                const SizedBox(height: 16),

                // Security Card
                _buildSecurityCard(colorScheme, theme, l10n, delegate),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _pickAndUploadImage(ImageSource source, Delegate? delegate) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        imageQuality: 70, // تقليل الجودة لتوفير المساحة وسرعة التحميل
        maxWidth: 800,
        maxHeight: 800,
      );

      if (picked == null) return;

      setState(() => _isUploadingPhoto = true);

      final file = File(picked.path);
      final uid = delegate?.uid ?? _currentUser?.uid;
      if (uid == null) {
        throw Exception('لم يتم العثور على معرّف المستخدم');
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final storageRef = FirebaseStorage.instance.ref(
        'delegate_documents/$uid/personalPhoto_$timestamp.jpg',
      );
      final uploadTask = await storageRef.putFile(file);
      final downloadUrl = await uploadTask.ref.getDownloadURL();

      final firestore = FirebaseFirestore.instance;

      // 1. تحديث وثيقة المستخدم في users
      await firestore.collection('users').doc(uid).set({
        'photoURL': downloadUrl,
        'profileImageUrl': downloadUrl,
        'personalPhotoURL': downloadUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final userQuery = await firestore
          .collection('users')
          .where('uid', isEqualTo: uid)
          .get();
      for (final doc in userQuery.docs) {
        await doc.reference.set({
          'photoURL': downloadUrl,
          'profileImageUrl': downloadUrl,
          'personalPhotoURL': downloadUrl,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      // 2. تحديث وثيقة المندوب/المشرف في الشركات والمنظمات
      if (delegate != null && delegate.companyUID.isNotEmpty) {
        final orgsSnap = await firestore.collection('organizations').get();
        for (final orgDoc in orgsSnap.docs) {
          final delRef = firestore
              .collection('organizations')
              .doc(orgDoc.id)
              .collection('companies')
              .doc(delegate.companyUID)
              .collection('delegates')
              .doc(delegate.uid);
          final check = await delRef.get();
          if (check.exists) {
            final currentDocs = (check.data()?['documents'] as List<dynamic>?) ?? [];
            final updatedDocs = <Map<String, dynamic>>[];
            bool found = false;
            for (final d in currentDocs) {
              if (d is Map && d['documentKey'] == 'personalPhoto') {
                found = true;
                updatedDocs.add({
                  ...Map<String, dynamic>.from(d),
                  'documentURL': downloadUrl,
                  'documentStatus': 'approved',
                  'uploadedAt': DateTime.now().toIso8601String(),
                });
              } else if (d is Map) {
                updatedDocs.add(Map<String, dynamic>.from(d));
              }
            }
            if (!found) {
              updatedDocs.add({
                'documentKey': 'personalPhoto',
                'documentStatus': 'approved',
                'documentURL': downloadUrl,
                'uploadedAt': DateTime.now().toIso8601String(),
              });
            }

            await delRef.set({
              'profileImageUrl': downloadUrl,
              'personalPhotoURL': downloadUrl,
              'photoURL': downloadUrl,
              'documents': updatedDocs,
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          }
        }
      }

      // 3. تحديث delegate_requests إن وجد
      try {
        final reqRef = firestore.collection('delegate_requests').doc(uid);
        final reqSnap = await reqRef.get();
        if (reqSnap.exists) {
          await reqRef.set({
            'profileImageUrl': downloadUrl,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      } catch (_) {}

      // 4. تحديث حساب Firebase Auth
      try {
        await _currentUser?.updatePhotoURL(downloadUrl);
        await _currentUser?.reload();
        _currentUser = _auth.currentUser;
      } catch (_) {}

      if (mounted) {
        context.read<AuthBloc>().add(CheckAutoLoginRequested());
        AppSnackBar.showSuccess(context, '✅ تم تحديث الصورة الشخصية بنجاح');
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(context, 'فشل رفع الصورة: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isUploadingPhoto = false);
      }
    }
  }

  Future<void> _removePhoto(Delegate? delegate) async {
    try {
      setState(() => _isUploadingPhoto = true);
      final uid = delegate?.uid ?? _currentUser?.uid;
      if (uid == null) return;

      final firestore = FirebaseFirestore.instance;
      await firestore.collection('users').doc(uid).set({
        'photoURL': FieldValue.delete(),
        'profileImageUrl': FieldValue.delete(),
        'personalPhotoURL': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (delegate != null && delegate.companyUID.isNotEmpty) {
        final orgsSnap = await firestore.collection('organizations').get();
        for (final orgDoc in orgsSnap.docs) {
          final delRef = firestore
              .collection('organizations')
              .doc(orgDoc.id)
              .collection('companies')
              .doc(delegate.companyUID)
              .collection('delegates')
              .doc(delegate.uid);
          final check = await delRef.get();
          if (check.exists) {
            final currentDocs = (check.data()?['documents'] as List<dynamic>?) ?? [];
            final updatedDocs = currentDocs.where((d) => d is Map && d['documentKey'] != 'personalPhoto').toList();
            await delRef.set({
              'profileImageUrl': FieldValue.delete(),
              'personalPhotoURL': FieldValue.delete(),
              'photoURL': FieldValue.delete(),
              'documents': updatedDocs,
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          }
        }
      }

      try {
        await _currentUser?.updatePhotoURL(null);
        await _currentUser?.reload();
        _currentUser = _auth.currentUser;
      } catch (_) {}

      if (mounted) {
        context.read<AuthBloc>().add(CheckAutoLoginRequested());
        AppSnackBar.showSuccess(context, 'تم حذف الصورة الشخصية');
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(context, 'فشل حذف الصورة: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isUploadingPhoto = false);
      }
    }
  }

  void _showPhotoOptionsSheet(BuildContext context, Delegate? delegate) {
    final photoUrl = delegate?.personalPhotoUrl ??
        (delegate?.documents
            .where((d) =>
                d.documentKey == DocumentKey.personalPhoto &&
                d.documentURL.isNotEmpty)
            .firstOrNull
            ?.documentURL) ??
        _currentUser?.photoURL;
    final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'الصورة الشخصية',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.camera_alt_rounded, color: Colors.blue),
                title: const Text('التقاط صورة بالكاميرا'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndUploadImage(ImageSource.camera, delegate);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded, color: Colors.purple),
                title: const Text('اختيار من معرض الصور'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndUploadImage(ImageSource.gallery, delegate);
                },
              ),
              if (hasPhoto)
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                  title: const Text('حذف الصورة الحالية', style: TextStyle(color: Colors.red)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _removePhoto(delegate);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Profile Header ─────────────────────────────────────────────
  Widget _buildProfileHeader(
    ColorScheme colorScheme,
    ThemeData theme,
    Delegate? delegate,
  ) {
    final displayName = delegate?.fullName ?? _currentUser?.displayName ?? 'مستخدم';
    final email = delegate?.email ?? _currentUser?.email ?? '';
    final photoUrl = delegate?.personalPhotoUrl ??
        (delegate?.documents
            .where((d) =>
                d.documentKey == DocumentKey.personalPhoto &&
                d.documentURL.isNotEmpty)
            .firstOrNull
            ?.documentURL) ??
        _currentUser?.photoURL;
    final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;

    return Card(
      elevation: 0,
      color: colorScheme.primaryContainer.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Avatar with edit/camera button
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: colorScheme.primary, width: 3),
                  ),
                  child: hasPhoto
                      ? ClipOval(
                          child: CachedNetworkImage(
                            imageUrl: photoUrl,
                            width: 96,
                            height: 96,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(
                              width: 96,
                              height: 96,
                              color: colorScheme.surfaceContainerHighest,
                              child: const Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2.5),
                                ),
                              ),
                            ),
                            errorWidget: (context, url, error) => CircleAvatar(
                              radius: 48,
                              backgroundColor: colorScheme.primaryContainer,
                              child: Text(
                                displayName.isNotEmpty
                                    ? displayName[0].toUpperCase()
                                    : 'U',
                                style: theme.textTheme.headlineLarge?.copyWith(
                                  color: colorScheme.onPrimaryContainer,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        )
                      : CircleAvatar(
                          radius: 48,
                          backgroundColor: colorScheme.primaryContainer,
                          child: Text(
                            displayName.isNotEmpty
                                ? displayName[0].toUpperCase()
                                : 'U',
                            style: theme.textTheme.headlineLarge?.copyWith(
                              color: colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                ),
                if (_isUploadingPhoto)
                  Positioned.fill(
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 3,
                          ),
                        ),
                      ),
                    ),
                  ),
                PositionedDirectional(
                  bottom: 0,
                  end: 0,
                  child: Material(
                    color: colorScheme.primary,
                    shape: const CircleBorder(),
                    elevation: 3,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _isUploadingPhoto
                          ? null
                          : () => _showPhotoOptionsSheet(context, delegate),
                      child: const Padding(
                        padding: EdgeInsets.all(7),
                        child: Icon(
                          Icons.camera_alt_rounded,
                          size: 17,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Display Name
            Text(
              displayName,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 4),

            // Email
            if (email.isNotEmpty)
              Text(
                email,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
          ],
        ),
      ),
    );
  }

  // ─── Personal Information Card ──────────────────────────────────
  Widget _buildPersonalInfoCard(
    ColorScheme colorScheme,
    ThemeData theme,
    AppLocalizations l10n,
    Delegate? delegate,
  ) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section Title
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.person_outline_rounded,
                    color: colorScheme.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'المعلومات الشخصية',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Display Name
            _buildInfoRow(
              icon: Icons.badge_outlined,
              label: 'الاسم',
              value: delegate?.fullName ?? _currentUser?.displayName ?? 'غير محدد',
              colorScheme: colorScheme,
              theme: theme,
              onEdit: () => _showEditInfoSheet(
                context,
                fieldType: 'name',
                initialValue: delegate?.fullName ?? _currentUser?.displayName ?? '',
                delegate: delegate,
              ),
            ),

            // Email
            _buildInfoRow(
              icon: Icons.email_outlined,
              label: 'البريد الإلكتروني',
              value: delegate?.email ?? _currentUser?.email ?? 'غير محدد',
              colorScheme: colorScheme,
              theme: theme,
              onEdit: () => _showEditInfoSheet(
                context,
                fieldType: 'email',
                initialValue: delegate?.email ?? _currentUser?.email ?? '',
                delegate: delegate,
              ),
            ),

            // Phone Number
            _buildInfoRow(
              icon: Icons.phone_outlined,
              label: 'رقم الموبايل',
              value: delegate?.phoneNumber ?? _currentUser?.phoneNumber ?? 'غير محدد',
              colorScheme: colorScheme,
              theme: theme,
              onEdit: () => _showEditInfoSheet(
                context,
                fieldType: 'phone',
                initialValue: delegate?.phoneNumber ?? _currentUser?.phoneNumber ?? '',
                delegate: delegate,
              ),
              showDivider: false,
            ),
          ],
        ),
      ),
    );
  }

  // ─── Security Card ──────────────────────────────────────────────
  Widget _buildSecurityCard(
    ColorScheme colorScheme,
    ThemeData theme,
    AppLocalizations l10n,
    Delegate? delegate,
  ) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section Title
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.security_rounded,
                    color: colorScheme.secondary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'الأمان',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Change Password Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _showChangePasswordSheet(context, delegate),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.secondaryContainer,
                  foregroundColor: colorScheme.onSecondaryContainer,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.lock_reset_rounded),
                label: const Text(
                  'تغيير كلمة المرور',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }


  // ─── Info Row Widget ────────────────────────────────────────────
  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    required ColorScheme colorScheme,
    required ThemeData theme,
    VoidCallback? onEdit,
    bool showDivider = true,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: colorScheme.primary, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              if (onEdit != null)
                IconButton(
                  icon: Icon(
                    Icons.edit_outlined,
                    color: colorScheme.primary,
                    size: 20,
                  ),
                  tooltip: 'تعديل $label',
                  onPressed: onEdit,
                ),
            ],
          ),
        ),
        if (showDivider) Divider(height: 1, color: colorScheme.outlineVariant),
      ],
    );
  }

  // ─── Edit Info Sheet (Email / Phone) ───────────────────────────
  void _showEditInfoSheet(
    BuildContext context, {
    required String fieldType,
    required String initialValue,
    Delegate? delegate,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _EditInfoBottomSheet(
        fieldType: fieldType,
        initialValue: initialValue,
        delegate: delegate,
      ),
    );
  }

  // ─── Change Password Sheet ──────────────────────────────────────
  void _showChangePasswordSheet(BuildContext context, Delegate? delegate) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ChangePasswordBottomSheet(delegate: delegate),
    );
  }

}

// ═══════════════════════════════════════════════════════════════════
// Edit Email / Phone Bottom Sheet
// ═══════════════════════════════════════════════════════════════════

class _EditInfoBottomSheet extends StatefulWidget {
  final String fieldType; // 'email' or 'phone'
  final String initialValue;
  final Delegate? delegate;

  const _EditInfoBottomSheet({
    required this.fieldType,
    required this.initialValue,
    this.delegate,
  });

  @override
  State<_EditInfoBottomSheet> createState() => _EditInfoBottomSheetState();
}

class _EditInfoBottomSheetState extends State<_EditInfoBottomSheet> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _controller;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _updateInfo() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final newValue = _controller.text.trim();
      final isName = widget.fieldType == 'name';
      final isEmail = widget.fieldType == 'email';

      // 1. Update Firestore 'users' collection
      final db = FirebaseFirestore.instance;
      final fbUser = FirebaseAuth.instance.currentUser;

      Query query = db.collection('users');
      if (widget.delegate != null && widget.delegate!.uid.isNotEmpty) {
        query = query.where('uid', isEqualTo: widget.delegate!.uid);
      } else if (fbUser != null) {
        query = query.where('uid', isEqualTo: fbUser.uid);
      }

      var snapshot = await query.limit(1).get();
      if (snapshot.docs.isEmpty && widget.delegate != null) {
        if (isEmail && widget.delegate!.phoneNumber.isNotEmpty) {
          snapshot = await db
              .collection('users')
              .where('phoneNumber', isEqualTo: widget.delegate!.phoneNumber)
              .limit(1)
              .get();
        } else if (!isEmail && !isName &&
            widget.delegate!.email != null &&
            widget.delegate!.email!.isNotEmpty) {
          snapshot = await db
              .collection('users')
              .where('email', isEqualTo: widget.delegate!.email)
              .limit(1)
              .get();
        }
      }

      if (snapshot.docs.isNotEmpty) {
        final doc = snapshot.docs.first;
        if (isName) {
          await doc.reference.update({
            'fullName': newValue,
            'name': newValue,
            'displayName': newValue,
          });
        } else {
          final fieldName = isEmail ? 'email' : 'phoneNumber';
          await doc.reference.update({fieldName: newValue});
        }
      }

      // Also update delegates collection if applicable
      if (widget.delegate != null && widget.delegate!.phoneNumber.isNotEmpty) {
        final delegateQuery = await db
            .collectionGroup('delegates')
            .where('phoneNumber', isEqualTo: widget.delegate!.phoneNumber)
            .get();
        for (final dDoc in delegateQuery.docs) {
          if (isName) {
            final names = newValue.split(RegExp(r'\s+'));
            final firstName = names.isNotEmpty ? names.first : newValue;
            final lastName = names.length > 1 ? names.last : '';
            final secondName = names.length > 2 ? names[1] : '';
            final thirdName = names.length > 3 ? names[2] : '';
            await dDoc.reference.update({
              'fullName': newValue,
              'firstName': firstName,
              'secondName': secondName,
              'thirdName': thirdName,
              'lastName': lastName,
            });
          } else {
            final fieldName = isEmail ? 'email' : 'phoneNumber';
            await dDoc.reference.update({fieldName: newValue});
          }
        }
      }

      // Update Firebase Auth if applicable
      if (fbUser != null) {
        if (isName) {
          try {
            await fbUser.updateDisplayName(newValue);
          } catch (_) {}
        } else if (isEmail) {
          try {
            await fbUser.verifyBeforeUpdateEmail(newValue);
          } catch (_) {}
        }
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isName
                  ? '✅ تم تحديث الاسم بنجاح'
                  : (isEmail
                      ? '✅ تم تحديث البريد الإلكتروني بنجاح'
                      : '✅ تم تحديث رقم الموبايل بنجاح'),
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );

        // Trigger auth reload
        context.read<AuthBloc>().add(CheckAutoLoginRequested());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ حدث خطأ أثناء التحديث: ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isName = widget.fieldType == 'name';
    final isEmail = widget.fieldType == 'email';
    final title = isName
        ? 'تعديل الاسم'
        : (isEmail ? 'تعديل البريد الإلكتروني' : 'تعديل رقم الموبايل');
    final label = isName
        ? 'الاسم بالكامل'
        : (isEmail ? 'البريد الإلكتروني الجديد' : 'رقم الموبايل الجديد');
    final icon = isName
        ? Icons.badge_outlined
        : (isEmail ? Icons.email_outlined : Icons.phone_outlined);

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + bottomInset),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 28, color: colorScheme.primary),
                  const SizedBox(width: 12),
                  Text(
                    title,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              TextFormField(
                controller: _controller,
                keyboardType: isName
                    ? TextInputType.name
                    : (isEmail ? TextInputType.emailAddress : TextInputType.phone),
                decoration: InputDecoration(
                  labelText: label,
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  prefixIcon: Icon(icon, color: colorScheme.onSurfaceVariant),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: colorScheme.outlineVariant, width: 1),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: colorScheme.primary, width: 2),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    if (isName) return 'يرجى إدخال الاسم';
                    return isEmail ? 'يرجى إدخال البريد الإلكتروني' : 'يرجى إدخال رقم الموبايل';
                  }
                  if (isName && value.trim().length < 3) {
                    return 'يجب أن يتكون الاسم من 3 أحرف على الأقل';
                  }
                  if (isEmail && !RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value.trim())) {
                    return 'يرجى إدخال بريد إلكتروني صحيح';
                  }
                  if (!isEmail && !isName && value.trim().length < 10) {
                    return 'يرجى إدخال رقم موبايل صحيح';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isLoading ? null : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text('إلغاء', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FilledButton(
                      onPressed: _isLoading ? null : _updateInfo,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('حفظ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Change Password Bottom Sheet
// ═══════════════════════════════════════════════════════════════════

class _ChangePasswordBottomSheet extends StatefulWidget {
  final Delegate? delegate;
  const _ChangePasswordBottomSheet({this.delegate});

  @override
  State<_ChangePasswordBottomSheet> createState() => _ChangePasswordBottomSheetState();
}

class _ChangePasswordBottomSheetState extends State<_ChangePasswordBottomSheet> {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscureCurrentPassword = true;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final String currentPass = _currentPasswordController.text.trim();
      final String newPass = _newPasswordController.text.trim();

      bool passwordUpdated = false;

      // 1. Try Firebase Auth (if user exists and has email)
      final fbUser = FirebaseAuth.instance.currentUser;
      if (fbUser != null && fbUser.email != null) {
        try {
          final credential = EmailAuthProvider.credential(
            email: fbUser.email!,
            password: currentPass,
          );
          await fbUser.reauthenticateWithCredential(credential);
          await fbUser.updatePassword(newPass);
          passwordUpdated = true;
        } catch (e) {
          // Might fail if they log in via anonymous/phone, proceed to Firestore as fallback.
        }
      }

      // 2. Try Firestore 'users' collection (for Admin / Marketing phone users)
      if (widget.delegate != null) {
        final delegate = widget.delegate!;
        final db = FirebaseFirestore.instance;
        
        // Find user by email or phone number
        Query query = db.collection('users');
        if (delegate.email != null && delegate.email!.isNotEmpty) {
           query = query.where('email', isEqualTo: delegate.email);
        } else if (delegate.phoneNumber.isNotEmpty) {
           query = query.where('phoneNumber', isEqualTo: delegate.phoneNumber);
        }

        final snapshot = await query.limit(1).get();
        if (snapshot.docs.isNotEmpty) {
          final doc = snapshot.docs.first;
          final data = doc.data() as Map<String, dynamic>;
          final storedPass = data['password'] ?? data['temporaryPassword'] ?? data['tempPassword'];

          if (storedPass == currentPass) {
             // Correct current password, update it
             await doc.reference.update({
               'password': newPass,
               'temporaryPassword': FieldValue.delete(),
               'tempPassword': FieldValue.delete(),
             });
             passwordUpdated = true;
          } else if (!passwordUpdated) {
             throw Exception('كلمة المرور الحالية غير صحيحة');
          }
        }
      }

      if (!passwordUpdated) {
        throw Exception('البيانات غير صحيحة أو لا يوجد حساب مرتبط بكلمة المرور هذه.');
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ تم تغيير كلمة المرور بنجاح'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required bool obscureText,
    required VoidCallback onToggleVisibility,
    required String? Function(String?) validator,
    required ColorScheme colorScheme,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        prefixIcon: Icon(Icons.lock_outline, color: colorScheme.onSurfaceVariant),
        suffixIcon: IconButton(
          icon: Icon(
            obscureText ? Icons.visibility_outlined : Icons.visibility_off_outlined,
            color: colorScheme.onSurfaceVariant,
          ),
          onPressed: onToggleVisibility,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.outlineVariant, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
      ),
      validator: validator,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + bottomInset),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock_reset_rounded, size: 28, color: colorScheme.primary),
                  const SizedBox(width: 12),
                  Text(
                    'تغيير كلمة المرور',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // Current Password
              _buildTextField(
                controller: _currentPasswordController,
                label: 'كلمة المرور الحالية',
                obscureText: _obscureCurrentPassword,
                colorScheme: colorScheme,
                onToggleVisibility: () {
                  setState(() => _obscureCurrentPassword = !_obscureCurrentPassword);
                },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'يرجى إدخال كلمة المرور الحالية';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              // New Password
              _buildTextField(
                controller: _newPasswordController,
                label: 'كلمة المرور الجديدة',
                obscureText: _obscureNewPassword,
                colorScheme: colorScheme,
                onToggleVisibility: () {
                  setState(() => _obscureNewPassword = !_obscureNewPassword);
                },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'يرجى إدخال كلمة المرور الجديدة';
                  }
                  if (value.length < 6) {
                    return 'كلمة المرور يجب أن تكون 6 أحرف على الأقل';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              // Confirm Password
              _buildTextField(
                controller: _confirmPasswordController,
                label: 'تأكيد كلمة المرور',
                obscureText: _obscureConfirmPassword,
                colorScheme: colorScheme,
                onToggleVisibility: () {
                  setState(() => _obscureConfirmPassword = !_obscureConfirmPassword);
                },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'يرجى تأكيد كلمة المرور';
                  }
                  if (value != _newPasswordController.text) {
                    return 'كلمة المرور غير متطابقة';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 32),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isLoading ? null : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text('إلغاء', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FilledButton(
                      onPressed: _isLoading ? null : _changePassword,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('تغيير', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

