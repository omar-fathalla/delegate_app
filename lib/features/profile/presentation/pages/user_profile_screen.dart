import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:delegate_app/features/profile/presentation/utils/document_review.dart';
import 'package:delegate_app/core/widgets/app_snack_bar.dart';
import 'package:delegate_app/core/widgets/tashil_maestro_dev_semantics.dart';
import 'package:delegate_app/features/hr/presentation/widgets/hr_adaptive_sheet.dart';
import 'package:delegate_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:delegate_app/features/auth/data/datasources/totp_mfa.dart';
import 'package:delegate_app/features/auth/presentation/widgets/totp_code_form.dart';
import 'package:delegate_app/features/profile/presentation/widgets/totp_enrollment_sheet.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:delegate_app/features/profile/data/models/delegate_model.dart';
import 'package:delegate_app/features/profile/data/staff_contact_api.dart';
import 'package:delegate_app/injection_container.dart' as di;

import '../../../../l10n/app_localizations.dart';
import 'package:delegate_app/features/profile/presentation/widgets/delegate_phone_change_sheet.dart';
import 'package:delegate_app/core/security/delegate_identity.dart';

/// صفحة الملف الشخصي للمستخدم
/// User Profile Screen with ability to change password and photo
/// TAS-72: whether the profile screen offers the name / email / phone edit.
/// Delegates cannot change these on their delegate documents (only the
/// staff-only `editDelegateProfile` callable may), so they ask a supervisor.
bool profileIdentityEditable(UserRole? role) => role != UserRole.delegate;

class UserProfileScreen extends StatefulWidget {
  final Delegate? delegate;

  /// False inside the web HR shell, where the inner page breadcrumb carries
  /// the title and the back button (TAS-157).
  final bool showAppBar;

  const UserProfileScreen({super.key, this.delegate, this.showAppBar = true});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final _auth = FirebaseAuth.instance;
  User? _currentUser;
  Delegate? _delegate;
  Map<String, dynamic>? _firestoreUserData;
  bool _isLoading = true;
  bool _isUploadingPhoto = false;

  @override
  void initState() {
    super.initState();
    _delegate = widget.delegate;
    _loadUserData();
  }

  Future<void> _changeDelegatePhone(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context)!;
    final newPhone = await showDelegatePhoneChangeSheet(context);
    if (newPhone == null || !mounted) return;
    setState(() {
      _firestoreUserData = {...?_firestoreUserData, 'phoneNumber': newPhone};
    });
    messenger.showSnackBar(SnackBar(content: Text(l10n.phoneChangeDone)));
    await _loadUserData();
  }

  Future<void> _loadUserData() async {
    _currentUser = _auth.currentUser;

    if (_delegate == null) {
      final authState = context.read<AuthBloc>().state;
      if (authState is AuthAuthenticated) {
        _delegate = authState.delegate;
      } else {
        _delegate = di.sl<AuthLocalDataSource>().getCachedDelegateData();
      }
    }

    // Immediately render with passed or cached data
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }

    // Background fetch fresh data from Firestore users collection
    await _fetchFirestoreData();
  }

  Future<void> _fetchFirestoreData() async {
    try {
      final firestore = FirebaseFirestore.instance;
      final targetUid = _delegate?.uid ?? DelegateIdentity.current(_auth);
      final targetPhone = _delegate?.phoneNumber ?? _currentUser?.phoneNumber;
      final targetEmail = _delegate?.email ?? _currentUser?.email;

      DocumentSnapshot<Map<String, dynamic>>? docSnap;

      if (targetUid != null && targetUid.isNotEmpty && targetUid != 'super-admin-login') {
        final doc = await firestore.collection('users').doc(targetUid).get();
        if (doc.exists && doc.data() != null) {
          docSnap = doc;
        }
      }

      // Delegates have no staff users doc; listing users by phone/email is
      // denied (M31 f7dbcf37) and is not needed for own-profile display.
      final isDelegateProfile = _delegate?.role == UserRole.delegate;
      if (!isDelegateProfile &&
          docSnap == null && targetPhone != null && targetPhone.isNotEmpty) {
        final query = await firestore
            .collection('users')
            .where('phoneNumber', isEqualTo: targetPhone)
            .limit(1)
            .get();
        if (query.docs.isNotEmpty) {
          docSnap = query.docs.first;
        } else {
          final normalizedPhone = targetPhone.replaceAll(RegExp(r'[^\d]'), '');
          if (normalizedPhone.isNotEmpty) {
            final queryNorm = await firestore
                .collection('users')
                .where('phoneNumber', isEqualTo: normalizedPhone)
                .limit(1)
                .get();
            if (queryNorm.docs.isNotEmpty) {
              docSnap = queryNorm.docs.first;
            }
          }
        }
      }

      if (!isDelegateProfile &&
          docSnap == null && targetEmail != null && targetEmail.isNotEmpty) {
        final queryEmail = await firestore
            .collection('users')
            .where('email', isEqualTo: targetEmail)
            .limit(1)
            .get();
        if (queryEmail.docs.isNotEmpty) {
          docSnap = queryEmail.docs.first;
        }
      }

      if (docSnap != null && docSnap.exists && docSnap.data() != null && mounted) {
        final data = docSnap.data()!;
        setState(() {
          _firestoreUserData = data;
        });

        // TAS-49: copy a confirmed new Auth email into users/{uid}.
        if (!isDelegateProfile &&
            staffEmailNeedsSync(FirebaseAuth.instance.currentUser?.email, data['email'])) {
          StaffContactApi().syncEmail().catchError((Object _) {});
        }

        // Synchronize local cache if applicable
        if (_delegate is DelegateModel) {
          try {
            final json = (_delegate as DelegateModel).toLocalJson();
            if (data['displayName'] != null && data['displayName'].toString().isNotEmpty) {
              json['fullName'] = data['displayName'];
              json['firstName'] = data['displayName'];
            }
            if (data['email'] != null && data['email'].toString().isNotEmpty) {
              json['email'] = data['email'];
            }
            if (data['phoneNumber'] != null && data['phoneNumber'].toString().isNotEmpty) {
              json['phoneNumber'] = data['phoneNumber'];
            }
            final photo = data['photoURL'] ?? data['profileImageUrl'] ?? data['personalPhotoURL'];
            if (photo != null && photo.toString().isNotEmpty) {
              json['personalPhotoURL'] = photo;
              json['photoURL'] = photo;
            }
            final updated = DelegateModel.fromJson(json, docSnap.id);
            _delegate = updated;
            di.sl<AuthLocalDataSource>().cacheDelegateData(updated).ignore();
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('Error fetching Firestore user profile: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: colorScheme.surface,
        appBar: widget.showAppBar
            ? AppBar(
                title: Text(l10n.profile),
                backgroundColor: colorScheme.surface,
              )
            : null,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_currentUser == null && _delegate == null && _firestoreUserData == null) {
      return Scaffold(
        backgroundColor: colorScheme.surface,
        appBar: widget.showAppBar
            ? AppBar(
                title: Text(l10n.profile),
                backgroundColor: colorScheme.surface,
              )
            : null,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: colorScheme.error),
              const SizedBox(height: 16),
              Text(
                AppLocalizations.of(context)!.userNotFound,
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
      appBar: widget.showAppBar
          ? AppBar(
              title: Text(l10n.profile),
              backgroundColor: colorScheme.surface,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 1,
            )
          : null,
      body: BlocBuilder<AuthBloc, AuthState>(
        builder: (context, state) {
          Delegate? blocDelegate;
          if (state is AuthAuthenticated) {
            blocDelegate = state.delegate;
          }
          final effectiveDelegate = _delegate ?? blocDelegate;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Profile Header
                _buildProfileHeader(colorScheme, theme, effectiveDelegate),

                const SizedBox(height: 24),

                // Personal Information Card
                _buildPersonalInfoCard(colorScheme, theme, l10n, effectiveDelegate),

                const SizedBox(height: 16),

                // Security Card
                _buildSecurityCard(colorScheme, theme, l10n, effectiveDelegate),
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
      final uid = _delegate?.uid ?? delegate?.uid ?? _firestoreUserData?['uid'] ?? DelegateIdentity.current(_auth);
      if (uid == null || uid.isEmpty || uid == 'super-admin-login') {
        if (mounted) {
          AppSnackBar.showError(context, AppLocalizations.of(context)!.accountNotIdentified);
        }
        return;
      }
      final effectiveUid = uid;

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final storageRef = FirebaseStorage.instance.ref(
        'delegate_documents/$effectiveUid/personalPhoto_$timestamp.jpg',
      );
      final uploadTask = await storageRef.putFile(file);
      final downloadUrl = await uploadTask.ref.getDownloadURL();

      final firestore = FirebaseFirestore.instance;

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
            // Docs-pending: a re-upload from this screen is always
            // 'pending' until a supervisor / admin approves it; other
            // entries are copied exactly as stored.
            final updatedDocs = mergeReuploadedDocument(
              check.data()?['documents'],
              docType: 'personalPhoto',
              newUrl: downloadUrl,
            );

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

      // 1b. users doc is written after the delegate doc so a denied write
      // does not leave the two out of sync. TAS-72: only update an existing
      // doc, and only the signed-in user's own one; a merge-set here used to
      // create a role-less users doc (or be denied for a secondary profile).
      try {
        final usersRef = firestore.collection('users').doc(effectiveUid);
        if (_currentUser?.uid == effectiveUid &&
            (await usersRef.get()).exists) {
          await usersRef.update({
            'photoURL': downloadUrl,
            'profileImageUrl': downloadUrl,
            'personalPhotoURL': downloadUrl,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      } on FirebaseException catch (e) {
        throw Exception(e.message ?? 'فشل تحديث ملف المستخدم');
      }

      // 3. تحديث delegate_requests إن وجد. TAS-72: the rule only accepts a
      // new photo URL when the request's `documents` list carries a matching
      // pending entry, so send the merged list with it.
      try {
        final reqRef = firestore.collection('delegate_requests').doc(effectiveUid);
        final reqSnap = await reqRef.get();
        if (reqSnap.exists) {
          await reqRef.set({
            'profileImageUrl': downloadUrl,
            'personalPhotoURL': downloadUrl,
            'documents': mergeReuploadedDocument(
              reqSnap.data()?['documents'],
              docType: 'personalPhoto',
              newUrl: downloadUrl,
            ),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      } catch (e) {
        debugPrint('delegate_requests photo sync failed: $e');
      }

      // 4. تحديث حساب Firebase Auth (فقط إذا كان نفس المستخدم صاحب الجلسة)
      try {
        if (_currentUser != null && _currentUser!.uid == effectiveUid) {
          await _currentUser?.updatePhotoURL(downloadUrl);
          await _currentUser?.reload();
          _currentUser = _auth.currentUser;
        }
      } catch (_) {}

      // 5. تحديث الحالة المعروضة في الشاشة والكاش المحلي
      if (mounted) {
        setState(() {
          _firestoreUserData ??= {};
          _firestoreUserData!['photoURL'] = downloadUrl;
          _firestoreUserData!['profileImageUrl'] = downloadUrl;
          _firestoreUserData!['personalPhotoURL'] = downloadUrl;
        });

        if (_delegate is DelegateModel) {
          final json = (_delegate as DelegateModel).toLocalJson();
          json['personalPhotoURL'] = downloadUrl;
          json['photoURL'] = downloadUrl;
          final updated = DelegateModel.fromJson(json, effectiveUid);
          _delegate = updated;
          di.sl<AuthLocalDataSource>().cacheDelegateData(updated).ignore();
        }

        context.read<AuthBloc>().add(CheckAutoLoginRequested());
        AppSnackBar.showSuccess(context, AppLocalizations.of(context)!.profilePhotoUpdated);
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(context, AppLocalizations.of(context)!.photoUploadFailed(e));
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
      final uid = _delegate?.uid ?? delegate?.uid ?? _firestoreUserData?['uid'] ?? DelegateIdentity.current(_auth);
      if (uid == null || uid.isEmpty || uid == 'super-admin-login') {
        if (mounted) {
          AppSnackBar.showError(context, AppLocalizations.of(context)!.accountNotIdentified);
        }
        return;
      }
      final effectiveUid = uid;

      final firestore = FirebaseFirestore.instance;
      // 1. حذف الصورة من وثيقة المستخدم المحددة فقط في users. TAS-72: only
      // the signed-in user's own existing doc (no role-less create).
      final usersRef = firestore.collection('users').doc(effectiveUid);
      if (_currentUser?.uid == effectiveUid && (await usersRef.get()).exists) {
        await usersRef.update({
          'photoURL': FieldValue.delete(),
          'profileImageUrl': FieldValue.delete(),
          'personalPhotoURL': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

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
        if (_currentUser != null && _currentUser!.uid == effectiveUid) {
          await _currentUser?.updatePhotoURL(null);
          await _currentUser?.reload();
          _currentUser = _auth.currentUser;
        }
      } catch (_) {}

      if (mounted) {
        setState(() {
          if (_firestoreUserData != null) {
            _firestoreUserData!.remove('photoURL');
            _firestoreUserData!.remove('profileImageUrl');
            _firestoreUserData!.remove('personalPhotoURL');
          }
        });

        if (_delegate is DelegateModel) {
          final json = (_delegate as DelegateModel).toLocalJson();
          json.remove('personalPhotoURL');
          json.remove('photoURL');
          final updated = DelegateModel.fromJson(json, effectiveUid);
          _delegate = updated;
          di.sl<AuthLocalDataSource>().cacheDelegateData(updated).ignore();
        }

        context.read<AuthBloc>().add(CheckAutoLoginRequested());
        AppSnackBar.showSuccess(context, AppLocalizations.of(context)!.profilePhotoDeleted);
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(context, AppLocalizations.of(context)!.photoDeleteFailed(e));
      }
    } finally {
      if (mounted) {
        setState(() => _isUploadingPhoto = false);
      }
    }
  }

  void _showPhotoOptionsSheet(BuildContext context, Delegate? delegate) {
    final photoUrl = _firestoreUserData?['photoURL'] ??
        _firestoreUserData?['profileImageUrl'] ??
        _firestoreUserData?['personalPhotoURL'] ??
        delegate?.personalPhotoUrl ??
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
              Text(
                AppLocalizations.of(context)!.profilePhoto,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.camera_alt_rounded, color: Colors.blue),
                title: Text(AppLocalizations.of(context)!.takePhotoCamera),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndUploadImage(ImageSource.camera, delegate);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded, color: Colors.purple),
                title: Text(AppLocalizations.of(context)!.chooseFromGallery),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndUploadImage(ImageSource.gallery, delegate);
                },
              ),
              if (hasPhoto)
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                  title: Text(AppLocalizations.of(context)!.removeCurrentPhoto, style: TextStyle(color: Colors.red)),
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

  String _getRoleDisplayName(Delegate? delegate, Map<String, dynamic>? firestoreData) {
    final roleStr = firestoreData?['role']?.toString().toLowerCase() ?? '';
    if (delegate?.role == UserRole.superAdmin || roleStr == 'super-admin' || roleStr == 'super_admin') {
      return AppLocalizations.of(context)!.roleSuperAdmin2;
    }
    if (delegate?.role == UserRole.technicalSupport || roleStr.contains('technical')) {
      return AppLocalizations.of(context)!.roleTechSupport2;
    }
    if (delegate?.role == UserRole.organizationAdmin || roleStr.contains('organization')) {
      return AppLocalizations.of(context)!.roleOrgAdmin2;
    }
    if (delegate?.role == UserRole.admin || roleStr.contains('company-admin')) {
      return AppLocalizations.of(context)!.roleCompanyAdmin2;
    }
    if (delegate?.role == UserRole.hr || roleStr == 'hr' || roleStr.contains('hr')) {
      return AppLocalizations.of(context)!.roleHrOfficer;
    }
    if (delegate?.role == UserRole.accountant || roleStr.contains('account')) {
      return AppLocalizations.of(context)!.roleAccountant;
    }
    if (delegate?.role == UserRole.marketing || delegate?.role == UserRole.marketingPromotion || roleStr.contains('marketing')) {
      return AppLocalizations.of(context)!.roleMarketing2;
    }
    if (delegate?.position == DelegatePosition.supervisor) {
      return AppLocalizations.of(context)!.roleSupervisor;
    }
    return AppLocalizations.of(context)!.roleDelegate;
  }

  // ─── Profile Header ─────────────────────────────────────────────
  Widget _buildProfileHeader(
    ColorScheme colorScheme,
    ThemeData theme,
    Delegate? delegate,
  ) {
    final rawName = _firestoreUserData?['displayName'] ??
        _firestoreUserData?['fullName'] ??
        delegate?.fullName ??
        _currentUser?.displayName ??
        '';
    final displayName = rawName.isNotEmpty ? rawName : AppLocalizations.of(context)!.defaultUserName;

    final rawEmail = _firestoreUserData?['email'] ??
        delegate?.email ??
        _currentUser?.email ??
        '';
    final email = rawEmail;

    final photoUrl = _firestoreUserData?['photoURL'] ??
        _firestoreUserData?['profileImageUrl'] ??
        _firestoreUserData?['personalPhotoURL'] ??
        delegate?.personalPhotoUrl ??
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
                                    : 'O',
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
                                : 'O',
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

            const SizedBox(height: 6),

            // Role Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: colorScheme.primary.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Text(
                _getRoleDisplayName(delegate, _firestoreUserData),
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
              ),
            ),

            const SizedBox(height: 6),

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
    final rawName = _firestoreUserData?['displayName'] ??
        _firestoreUserData?['fullName'] ??
        delegate?.fullName ??
        _currentUser?.displayName ??
        '';
    final displayName = rawName.isNotEmpty ? rawName : AppLocalizations.of(context)!.defaultUserName;

    final rawEmail = _firestoreUserData?['email'] ??
        delegate?.email ??
        _currentUser?.email ??
        '';
    final email = rawEmail;

    final rawPhone = _firestoreUserData?['phoneNumber'] ??
        delegate?.phoneNumber ??
        _currentUser?.phoneNumber ??
        '';
    final phone = rawPhone;

    // TAS-72: a delegate cannot change its own name, email or phone on the
    // delegate documents (the rules only let `editDelegateProfile` do that,
    // and that callable is staff-only). The users doc alone would succeed and
    // leave the two out of sync, so the edit buttons are hidden for
    // delegates and they are told to ask their supervisor. Phone/ID changes
    // with OTP come with TAS-112.
    final canEditIdentity = profileIdentityEditable(delegate?.role);

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
                  AppLocalizations.of(context)!.personalInfo,
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
              label: AppLocalizations.of(context)!.nameLabel,
              value: displayName,
              colorScheme: colorScheme,
              theme: theme,
              onEdit: !canEditIdentity
                  ? null
                  : () => _showEditInfoSheet(
                        context,
                        fieldType: 'name',
                        initialValue: displayName,
                        delegate: delegate,
                      ),
            ),

            // Email
            _buildInfoRow(
              icon: Icons.email_outlined,
              label: AppLocalizations.of(context)!.emailLabel,
              value: email,
              colorScheme: colorScheme,
              theme: theme,
              onEdit: !canEditIdentity
                  ? null
                  : () => _showEditInfoSheet(
                        context,
                        fieldType: 'email',
                        initialValue: email,
                        delegate: delegate,
                      ),
            ),

            // Phone Number
            _buildInfoRow(
              icon: Icons.phone_outlined,
              label: AppLocalizations.of(context)!.phoneNumberLabel,
              value: phone,
              colorScheme: colorScheme,
              theme: theme,
              maestroValueIdentifier: 'tashil_profile_phone_value',
              // TAS-112: a delegate changes its phone with an OTP on the new
              // number (server callables); staff keep the direct edit.
              onEdit: !canEditIdentity
                  ? (delegate?.role == UserRole.delegate
                      ? () => _changeDelegatePhone(context)
                      : null)
                  : () => _showEditInfoSheet(
                        context,
                        fieldType: 'phone',
                        initialValue: phone,
                        delegate: delegate,
                      ),
              showDivider: false,
            ),
            if (!canEditIdentity) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 18, color: colorScheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context)!.profileIdentityEditViaSupervisor,
                      key: const Key('profile_identity_locked_hint'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
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
                  AppLocalizations.of(context)!.securitySection,
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
                label: Text(
                  AppLocalizations.of(context)!.changePassword,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            // TAS-207: TOTP enrollment, super admin only.
            TwoStepVerificationButton(
              role: delegate?.role,
              rawRole: _firestoreUserData?['role']?.toString(),
            ),
          ],
        ),
      ),
    );
  }


  // ─── Info Row Widget ────────────────────────────────────────────
  Widget _buildInfoValueText({
    required String value,
    required ThemeData theme,
    required ColorScheme colorScheme,
    String? maestroValueIdentifier,
  }) {
    final text = Text(
      value,
      style: theme.textTheme.bodyLarge?.copyWith(
        fontWeight: FontWeight.w600,
        color: colorScheme.onSurface,
      ),
    );
    if (maestroValueIdentifier == null) {
      return text;
    }
    return tashilMaestroDevSemantics(
      identifier: maestroValueIdentifier,
      label: value,
      child: text,
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    required ColorScheme colorScheme,
    required ThemeData theme,
    VoidCallback? onEdit,
    bool showDivider = true,
    String? maestroValueIdentifier,
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
                    _buildInfoValueText(
                      value: value,
                      theme: theme,
                      colorScheme: colorScheme,
                      maestroValueIdentifier: maestroValueIdentifier,
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
                  tooltip: AppLocalizations.of(context)!.editField(label),
                  onPressed: onEdit,
                ),
            ],
          ),
        ),
        if (showDivider) Divider(height: 1, color: colorScheme.outlineVariant),
      ],
    );
  }

  // ─── Edit Info Sheet (Name / Email / Phone) ───────────────────
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
        firestoreData: _firestoreUserData,
        onUpdated: (fType, nVal) {
          setState(() {
            _firestoreUserData ??= {};
            if (fType == 'name') {
              _firestoreUserData!['displayName'] = nVal;
              _firestoreUserData!['fullName'] = nVal;
              _firestoreUserData!['name'] = nVal;
            } else if (fType == 'email') {
              _firestoreUserData!['email'] = nVal;
            } else if (fType == 'phone') {
              _firestoreUserData!['phoneNumber'] = nVal;
            }

            if (_delegate is DelegateModel) {
              final json = (_delegate as DelegateModel).toLocalJson();
              if (fType == 'name') {
                json['fullName'] = nVal;
                json['firstName'] = nVal;
              } else if (fType == 'email') {
                json['email'] = nVal;
              } else if (fType == 'phone') {
                json['phoneNumber'] = nVal;
              }
              final uid = _delegate?.uid ?? _firestoreUserData?['uid'] ?? DelegateIdentity.current(_auth) ?? '';
              final updated = DelegateModel.fromJson(json, uid);
              _delegate = updated;
              di.sl<AuthLocalDataSource>().cacheDelegateData(updated).ignore();
            }
          });
        },
      ),
    );
  }

  // ─── Change Password Sheet ──────────────────────────────────────
  void _showChangePasswordSheet(BuildContext context, Delegate? delegate) {
    showUserChangePasswordSheet(
      context,
      delegate: delegate,
      firestoreData: _firestoreUserData,
    );
  }

}

// ═══════════════════════════════════════════════════════════════════
// Edit Email / Phone / Name Bottom Sheet
// ═══════════════════════════════════════════════════════════════════

class _EditInfoBottomSheet extends StatefulWidget {
  final String fieldType; // 'name', 'email', or 'phone'
  final String initialValue;
  final Delegate? delegate;
  final Map<String, dynamic>? firestoreData;
  final void Function(String fieldType, String newValue)? onUpdated;

  const _EditInfoBottomSheet({
    required this.fieldType,
    required this.initialValue,
    this.delegate,
    this.firestoreData,
    this.onUpdated,
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

      final fbUser = FirebaseAuth.instance.currentUser;
      var storedValue = newValue;

      if (isEmail) {
        // TAS-49: the email changes in Firebase Auth only after the user
        // confirms it from the link; the profile then copies it into
        // users/{uid} (staffEmailNeedsSync + updateOwnStaffContact).
        if (fbUser == null) throw Exception('سجّل الدخول من جديد.');
        await fbUser.verifyBeforeUpdateEmail(newValue);
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('اتبعت رابط تأكيد على الإيميل الجديد. الإيميل هيتغيّر بعد ما تفتح الرابط.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      if (!isName) {
        // TAS-49: phone goes through the server (uniqueness check). Other
        // users' docs and delegate docs are no longer rewritten from here.
        storedValue = await StaffContactApi().updatePhone(newValue);
      } else {
        final db = FirebaseFirestore.instance;
        final fbUser = FirebaseAuth.instance.currentUser;

        // Determine effective user doc id
        String? effectiveDocId = widget.firestoreData?['uid'] ?? widget.delegate?.uid;

        // 1. Update direct doc in users if known
        if (effectiveDocId != null && effectiveDocId.isNotEmpty && effectiveDocId != 'super-admin-login') {
          final docRef = db.collection('users').doc(effectiveDocId);
          final docSnap = await docRef.get();
          if (docSnap.exists) {
            if (isName) {
              await docRef.set({
                'displayName': newValue,
                'fullName': newValue,
                'name': newValue,
                'updatedAt': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));
            } else {
              final fieldName = isEmail ? 'email' : 'phoneNumber';
              await docRef.set({
                fieldName: newValue,
                'updatedAt': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));
            }
          }
        }

        // 2. Query users collection by phone / email to ensure complete sync
        // Skip for delegates: users-list queries are unprovable and denied.
        final phone = widget.firestoreData?['phoneNumber'] ?? widget.delegate?.phoneNumber;
        final email = widget.firestoreData?['email'] ?? widget.delegate?.email;

        final queryDocs = <DocumentReference>[];
        final isDelegateUpdate = widget.delegate?.role == UserRole.delegate;
        if (!isDelegateUpdate && phone != null && phone.isNotEmpty) {
          final q = await db.collection('users').where('phoneNumber', isEqualTo: phone).get();
          queryDocs.addAll(q.docs.map((d) => d.reference));
        }
        if (!isDelegateUpdate && email != null && email.isNotEmpty) {
          final q = await db.collection('users').where('email', isEqualTo: email).get();
          queryDocs.addAll(q.docs.map((d) => d.reference));
        }

        for (final ref in queryDocs) {
          if (ref.id != effectiveDocId) {
            if (isName) {
              await ref.set({
                'displayName': newValue,
                'fullName': newValue,
                'name': newValue,
                'updatedAt': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));
            } else {
              final fieldName = isEmail ? 'email' : 'phoneNumber';
              await ref.set({
                fieldName: newValue,
                'updatedAt': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));
            }
          }
        }

        // 3. Update delegates collection if applicable
        if (phone != null && phone.isNotEmpty) {
          final delegateQuery = await db
              .collectionGroup('delegates')
              .where('phoneNumber', isEqualTo: phone)
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
                'updatedAt': FieldValue.serverTimestamp(),
              });
            } else {
              final fieldName = isEmail ? 'email' : 'phoneNumber';
              await dDoc.reference.update({
                fieldName: newValue,
                'updatedAt': FieldValue.serverTimestamp(),
              });
            }
          }
        }

        // 4. Update Firebase Auth if applicable
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
      }

      widget.onUpdated?.call(widget.fieldType, storedValue);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isName
                  ? AppLocalizations.of(context)!.nameUpdated
                  : (isEmail
                      ? AppLocalizations.of(context)!.emailUpdated
                      : AppLocalizations.of(context)!.phoneUpdated),
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
            content: Text(e is FirebaseFunctionsException
                ? staffContactErrorMessage(e)
                : '❌ حدث خطأ أثناء التحديث: ${e.toString().replaceAll('Exception: ', '')}'),
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
        ? AppLocalizations.of(context)!.editName2
        : (isEmail ? AppLocalizations.of(context)!.editEmail : AppLocalizations.of(context)!.editPhone);
    final label = isName
        ? AppLocalizations.of(context)!.fullName2
        : (isEmail ? AppLocalizations.of(context)!.newEmail : AppLocalizations.of(context)!.newPhone);
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
                    if (isName) return AppLocalizations.of(context)!.enterName;
                    return isEmail ? AppLocalizations.of(context)!.enterEmail : AppLocalizations.of(context)!.enterPhone;
                  }
                  if (isName && value.trim().length < 3) {
                    return AppLocalizations.of(context)!.nameMin3;
                  }
                  if (isEmail && !RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value.trim())) {
                    return AppLocalizations.of(context)!.invalidEmail2;
                  }
                  if (!isEmail && !isName && value.trim().length < 10) {
                    return AppLocalizations.of(context)!.invalidPhone;
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
                          : Text(AppLocalizations.of(context)!.saveAction, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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

/// Opens the profile screen's change-password sheet. The new password stays
/// in Firebase Auth only.
void showUserChangePasswordSheet(
  BuildContext context, {
  Delegate? delegate,
  Map<String, dynamic>? firestoreData,
  void Function(String newPassword)? onPasswordChanged,
}) {
  // Wide web windows get a dialog with the buttons in its footer (TAS-158).
  // Mobile and narrow windows keep the original bottom sheet unchanged.
  if (HrSheet.useDesktop(context)) {
    _showChangePasswordDialog(
      context,
      delegate: delegate,
      firestoreData: firestoreData,
      onPasswordChanged: onPasswordChanged,
    );
    return;
  }
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _ChangePasswordBottomSheet(
      delegate: delegate,
      firestoreData: firestoreData,
      onPasswordChanged: onPasswordChanged ?? (_) {},
    ),
  );
}

void _showChangePasswordDialog(
  BuildContext context, {
  Delegate? delegate,
  Map<String, dynamic>? firestoreData,
  void Function(String newPassword)? onPasswordChanged,
}) {
  final l10n = AppLocalizations.of(context)!;
  final formKey = GlobalKey<_ChangePasswordBottomSheetState>();
  // Mirrors the form's busy state for the footer buttons. Not disposed on
  // close: a submit still in flight may report to it after the dialog pops.
  final busy = ValueNotifier<bool>(false);
  showHrAdaptiveSheet<void>(
    context: context,
    title: l10n.changePassword,
    dialogWidth: 480,
    builder: (_) => _ChangePasswordBottomSheet(
      key: formKey,
      delegate: delegate,
      firestoreData: firestoreData,
      onPasswordChanged: onPasswordChanged ?? (_) {},
      inDialog: true,
      busy: busy,
    ),
    actions: (dialogContext) => [
      ValueListenableBuilder<bool>(
        valueListenable: busy,
        builder: (_, isBusy, _) => TextButton(
          key: const ValueKey('change_password_cancel'),
          onPressed: isBusy ? null : () => Navigator.of(dialogContext).pop(),
          child: const Text('إلغاء'),
        ),
      ),
      ValueListenableBuilder<bool>(
        valueListenable: busy,
        builder: (_, isBusy, _) => FilledButton(
          key: const ValueKey('change_password_submit'),
          onPressed: isBusy
              ? null
              : () => formKey.currentState?._changePassword(),
          child: isBusy
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.saveAction),
        ),
      ),
    ],
  );
}

class _ChangePasswordBottomSheet extends StatefulWidget {
  final Delegate? delegate;
  final Map<String, dynamic>? firestoreData;
  final void Function(String newPassword)? onPasswordChanged;

  /// True inside the web dialog: only the fields are built, the dialog frame
  /// draws the title and the buttons.
  final bool inDialog;

  /// Receives the busy state so the dialog footer can disable its buttons.
  final ValueNotifier<bool>? busy;

  const _ChangePasswordBottomSheet({
    super.key,
    this.delegate,
    this.firestoreData,
    this.onPasswordChanged,
    this.inDialog = false,
    this.busy,
  });

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

  void _setLoading(bool value) {
    setState(() => _isLoading = value);
    widget.busy?.value = value;
  }

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) return;
    _setLoading(true);

    try {
      final String currentPass = _currentPasswordController.text.trim();
      final String newPass = _newPasswordController.text.trim();

      final fbUser = FirebaseAuth.instance.currentUser;
      final email = (fbUser?.email ??
              widget.firestoreData?['email'] ??
              widget.delegate?.email ??
              '')
          .toString()
          .trim();
      if (email.isEmpty) {
        throw Exception('لا يوجد بريد إلكتروني مرتبط بهذا الحساب');
      }

      User user;
      if (fbUser != null && fbUser.email == email) {
        user = fbUser;
      } else {
        final signedIn = await _withTwoStep(
          () => FirebaseAuth.instance.signInWithEmailAndPassword(
            email: email,
            password: currentPass,
          ),
        );
        final signedInUser = signedIn?.user;
        if (signedIn == null) return;
        if (signedInUser == null) {
          throw Exception('كلمة المرور الحالية غير صحيحة');
        }
        user = signedInUser;
      }

      final credential = EmailAuthProvider.credential(
        email: email,
        password: currentPass,
      );
      final reauthed = await _withTwoStep(
        () => user.reauthenticateWithCredential(credential),
      );
      if (reauthed == null) return;
      await user.updatePassword(newPass);

      widget.onPasswordChanged?.call(newPass);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.passwordChanged),
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
        _setLoading(false);
      }
    }
  }

  /// Runs [action]. When the account has two-step verification (TAS-207),
  /// asks for the TOTP code and finishes the sign-in with it. Null when the
  /// user cancels the code step.
  Future<UserCredential?> _withTwoStep(
    Future<UserCredential> Function() action,
  ) async {
    try {
      return await action();
    } on FirebaseAuthMultiFactorException catch (error) {
      if (!mounted) return null;
      final resolver = error.resolver;
      if (totpHint(resolver.hints) == null) {
        throw Exception(mfaUnsupportedMessage);
      }
      UserCredential? resolved;
      final ok = await showTotpCodeSheet(
        context,
        subtitle: '$totpCodeHint\nمطلوب لتأكيد تغيير كلمة المرور.',
        onSubmit: (code) async {
          resolved = await resolveTotpSignIn(resolver, code);
        },
      );
      return ok ? resolved : null;
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

  /// The three password fields with their validators.
  List<Widget> _buildFields(BuildContext context, ColorScheme colorScheme) {
    return [
      // Current Password
      _buildTextField(
        controller: _currentPasswordController,
        label: AppLocalizations.of(context)!.currentPassword,
        obscureText: _obscureCurrentPassword,
        colorScheme: colorScheme,
        onToggleVisibility: () {
          setState(() => _obscureCurrentPassword = !_obscureCurrentPassword);
        },
        validator: (value) {
          if (value == null || value.isEmpty) {
            return AppLocalizations.of(context)!.enterCurrentPassword;
          }
          return null;
        },
      ),

      const SizedBox(height: 16),

      // New Password
      _buildTextField(
        controller: _newPasswordController,
        label: AppLocalizations.of(context)!.newPassword,
        obscureText: _obscureNewPassword,
        colorScheme: colorScheme,
        onToggleVisibility: () {
          setState(() => _obscureNewPassword = !_obscureNewPassword);
        },
        validator: (value) {
          if (value == null || value.isEmpty) {
            return AppLocalizations.of(context)!.enterNewPassword;
          }
          if (value.length < 6) {
            return AppLocalizations.of(context)!.passwordMin6;
          }
          return null;
        },
      ),

      const SizedBox(height: 16),

      // Confirm Password
      _buildTextField(
        controller: _confirmPasswordController,
        label: AppLocalizations.of(context)!.confirmPassword,
        obscureText: _obscureConfirmPassword,
        colorScheme: colorScheme,
        onToggleVisibility: () {
          setState(() => _obscureConfirmPassword = !_obscureConfirmPassword);
        },
        validator: (value) {
          if (value == null || value.isEmpty) {
            return AppLocalizations.of(context)!.enterConfirmPassword;
          }
          if (value != _newPasswordController.text) {
            return AppLocalizations.of(context)!.passwordsDontMatch;
          }
          return null;
        },
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    if (widget.inDialog) {
      return Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _buildFields(context, colorScheme),
        ),
      );
    }
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
                    AppLocalizations.of(context)!.changePassword,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              ..._buildFields(context, colorScheme),

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
                          : Text(AppLocalizations.of(context)!.saveAction, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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

