import 'package:delegate_app/core/design/bidi.dart';
import 'package:intl/intl.dart' hide TextDirection, Bidi;
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:delegate_app/core/design/widgets/skeleton.dart';
import 'package:delegate_app/core/design/widgets/snackbars.dart';
import 'package:delegate_app/core/design/widgets/loading_indicator.dart';
import 'package:delegate_app/core/design/tokens.dart';
import 'package:delegate_app/core/widgets/storage_resolved_image.dart';
import 'package:delegate_app/core/storage/storage_media.dart';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:material_ui/material_ui.dart';
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

  /// The national ID is masked until the person asks to see it.
  bool _showNationalId = false;
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
        // Known layout: skeletons of the header and the info card (P-08).
        body: ListView(
          key: const Key('profile_skeleton'),
          padding: const EdgeInsets.all(TashilSpacing.page),
          children: const [
            SummaryCardSkeleton(facts: 0),
            SizedBox(height: TashilSpacing.xl),
            SummaryCardSkeleton(facts: 2),
          ],
        ),
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
              const SizedBox(height: TashilSpacing.lg),
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
            padding: const EdgeInsets.all(TashilSpacing.page),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Profile Header
                _buildProfileHeader(colorScheme, theme, effectiveDelegate),

                const SizedBox(height: TashilSpacing.xl),

                // Personal Information Card
                _buildPersonalInfoCard(colorScheme, theme, l10n, effectiveDelegate),

                // TAS-387: the delegate's own data that was stored but never
                // shown (code, national ID, city, chains, join date).
                ..._buildWorkInfo(colorScheme, theme, l10n, effectiveDelegate),

                const SizedBox(height: TashilSpacing.xl),

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
      // TAS-331: the path is the source of truth; the download URL is only
      // written for older app versions while write_legacy_storage_urls is on.
      final photoPath = uploadTask.ref.fullPath;
      final downloadUrl = await LegacyStorageUrls.urlFor(uploadTask.ref) ?? '';

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
              newPath: photoPath,
            );

            await delRef.set({
              'profileImageUrl': downloadUrl,
              'personalPhotoURL': downloadUrl,
              'photoURL': downloadUrl,
              'profileImagePath': photoPath,
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
            'profileImagePath': photoPath,
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
            'profileImagePath': photoPath,
            'documents': mergeReuploadedDocument(
              reqSnap.data()?['documents'],
              docType: 'personalPhoto',
              newUrl: downloadUrl,
              newPath: photoPath,
            ),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      } catch (e) {
        debugPrint('delegate_requests photo sync failed: $e');
      }

      // 4. تحديث حساب Firebase Auth (فقط إذا كان نفس المستخدم صاحب الجلسة)
      try {
        if (_currentUser != null &&
            _currentUser!.uid == effectiveUid &&
            downloadUrl.isNotEmpty) {
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
          _firestoreUserData!['profileImagePath'] = photoPath;
        });

        if (_delegate is DelegateModel) {
          final json = (_delegate as DelegateModel).toLocalJson();
          json['personalPhotoURL'] = downloadUrl;
          json['photoURL'] = downloadUrl;
          json['profileImagePath'] = photoPath;
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
          'profileImagePath': FieldValue.delete(),
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
              'profileImagePath': FieldValue.delete(),
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

  /// TAS-331: the photo on the users doc, path first; null when unset
  /// (an empty URL written while write_legacy_storage_urls is off falls
  /// through to the next source).
  String? _userDocPhoto() {
    final d = _firestoreUserData;
    if (d == null) return null;
    String? firstUrl;
    for (final k in const ['photoURL', 'profileImageUrl', 'personalPhotoURL']) {
      final v = d[k];
      if (v is String && v.trim().isNotEmpty) {
        firstUrl = v.trim();
        break;
      }
    }
    final v = StorageMediaRef.pickFresh(path: d['profileImagePath'], url: firstUrl);
    return v.isEmpty ? null : v;
  }

  void _showPhotoOptionsSheet(BuildContext context, Delegate? delegate) {
    final photoUrl = _userDocPhoto() ??
        delegate?.personalPhotoUrl ??
        _currentUser?.photoURL;
    final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;

    // TAS-355 (C-28): one drag handle (the theme's), shape from the theme;
    // neutral icons, the destructive "remove" in error.
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsetsDirectional.only(bottom: TashilSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppLocalizations.of(context)!.profilePhoto,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: TashilSpacing.md),
              ListTile(
                leading: Icon(Icons.camera_alt_rounded, color: cs.onSurfaceVariant),
                title: Text(AppLocalizations.of(context)!.takePhotoCamera),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndUploadImage(ImageSource.camera, delegate);
                },
              ),
              ListTile(
                leading: Icon(Icons.photo_library_rounded, color: cs.onSurfaceVariant),
                title: Text(AppLocalizations.of(context)!.chooseFromGallery),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndUploadImage(ImageSource.gallery, delegate);
                },
              ),
              if (hasPhoto)
                ListTile(
                  leading: Icon(Icons.delete_outline_rounded, color: cs.error),
                  title: Text(
                    AppLocalizations.of(context)!.removeCurrentPhoto,
                    style: TextStyle(color: cs.error),
                  ),
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
    final l10n = AppLocalizations.of(context)!;
    final tt = theme.textTheme;
    final rawName = _firestoreUserData?['displayName'] ??
        _firestoreUserData?['fullName'] ??
        delegate?.fullName ??
        _currentUser?.displayName ??
        '';
    final displayName = rawName.isNotEmpty ? rawName : l10n.defaultUserName;

    final photoUrl = _userDocPhoto() ??
        delegate?.personalPhotoUrl ??
        _currentUser?.photoURL;
    final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;
    const avatar = 72.0;

    Widget initial() => CircleAvatar(
      radius: avatar / 2,
      backgroundColor: colorScheme.primaryContainer,
      child: Text(
        displayName.isNotEmpty ? displayName.substring(0, 1) : '؟',
        style: tt.headlineSmall?.copyWith(
          color: colorScheme.onPrimaryContainer,
        ),
      ),
    );

    // Read-only values: an icon and text, never a chip (TAS-384).
    Widget fact(IconData icon, String text, {Key? key}) => Padding(
      padding: const EdgeInsetsDirectional.only(top: TashilSpacing.xs),
      child: Row(
        key: key,
        children: [
          Icon(icon, size: 16, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: TashilSpacing.xs),
          Flexible(
            child: Text(
              text,
              style: tt.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );

    final org = (delegate?.companyName.isNotEmpty ?? false)
        ? delegate!.companyName
        : (delegate?.organizationName ?? '');

    // TAS-387 (user review 27 Nov 2026): a compact header like the home
    // card: avatar on the start side, the name in titleMedium (was a bold
    // headline), role and organisation as icon + text.
    return Card.filled(
      key: const Key('profile_header'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(TashilSpacing.lg),
        child: Row(
          children: [
            SizedBox.square(
              dimension: avatar + TashilSpacing.sm,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  if (hasPhoto)
                    ClipOval(
                      child: StorageResolvedImage.wrap(
                        pathOrUrl: photoUrl,
                        builder: (context, resolvedUrl) => CachedNetworkImage(
                          imageUrl: resolvedUrl,
                          width: avatar,
                          height: avatar,
                          fit: BoxFit.cover,
                          placeholder: (context, url) =>
                              const Skeleton.circle(size: avatar),
                          errorWidget: (context, url, error) => initial(),
                        ),
                      ),
                    )
                  else
                    initial(),
                  if (_isUploadingPhoto)
                    const SizedBox.square(
                      dimension: avatar,
                      child: Center(
                        child: LoadingIndicator(size: 40, contained: true),
                      ),
                    ),
                  PositionedDirectional(
                    bottom: -TashilSpacing.xs,
                    end: -TashilSpacing.xs,
                    // Card-icon rule: IconButton.filled with a tooltip.
                    child: IconButton.filled(
                      key: const Key('profile_photo_button'),
                      tooltip: l10n.profilePhoto,
                      style: IconButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      iconSize: 18,
                      onPressed: _isUploadingPhoto
                          ? null
                          : () => _showPhotoOptionsSheet(context, delegate),
                      icon: const Icon(Symbols.photo_camera_rounded),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: TashilSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    key: const Key('profile_name'),
                    // Same size as the home greeting (user review 27 Nov).
                    style: tt.titleMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  fact(
                    Symbols.badge_rounded,
                    _getRoleDisplayName(delegate, _firestoreUserData),
                    key: const Key('profile_role'),
                  ),
                  if (org.isNotEmpty) fact(Symbols.storefront_rounded, org),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A section title above its card (same as «آخر النشاط» on home).
  Widget _sectionTitle(IconData icon, String title) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        start: TashilSpacing.xs,
        bottom: TashilSpacing.sm,
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: cs.primary),
          const SizedBox(width: TashilSpacing.sm),
          Text(title, style: Theme.of(context).textTheme.titleSmall),
        ],
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
    final displayName = rawName.isNotEmpty ? rawName : l10n.defaultUserName;
    final String email = _firestoreUserData?['email'] ??
        delegate?.email ??
        _currentUser?.email ??
        '';
    final String phone = _firestoreUserData?['phoneNumber'] ??
        delegate?.phoneNumber ??
        _currentUser?.phoneNumber ??
        '';

    // TAS-72: a delegate cannot change its own name, email or phone on the
    // delegate documents (only the staff callable can); they ask their
    // supervisor. Phone changes with OTP come with TAS-112.
    final canEditIdentity = profileIdentityEditable(delegate?.role);

    final rows = <Widget>[
      // The name is in the header; it is repeated here only where it can be
      // edited.
      if (canEditIdentity)
        _buildInfoRow(
          icon: Symbols.badge_rounded,
          label: l10n.nameLabel,
          value: displayName,
          colorScheme: colorScheme,
          theme: theme,
          onEdit: () => _showEditInfoSheet(
            context,
            fieldType: 'name',
            initialValue: displayName,
            delegate: delegate,
          ),
        ),
      _buildInfoRow(
        icon: Symbols.call_rounded,
        label: l10n.phoneNumberLabel,
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
      ),
      // An empty e-mail row said nothing; it shows only when there is one
      // or it can be added.
      if (email.isNotEmpty || canEditIdentity)
        _buildInfoRow(
          icon: Symbols.mail_rounded,
          label: l10n.emailLabel,
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
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(Symbols.person_rounded, l10n.personalInfo),
        Card.filled(
          key: const Key('profile_info_card'),
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0)
                  const Divider(height: 1, indent: TashilSpacing.xxl * 2),
                rows[i],
              ],
            ],
          ),
        ),
        if (!canEditIdentity)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              TashilSpacing.xs,
              TashilSpacing.sm,
              TashilSpacing.xs,
              0,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Symbols.info_rounded,
                  size: 16,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: TashilSpacing.xs),
                Expanded(
                  child: Text(
                    l10n.profileIdentityEditViaSupervisor,
                    key: const Key('profile_identity_locked_hint'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// «بيانات العمل»: only for a field delegate or supervisor with data.
  /// Read-only list items (C-23); the code can be copied, the national ID
  /// is masked with a show/hide button.
  List<Widget> _buildWorkInfo(
    ColorScheme colorScheme,
    ThemeData theme,
    AppLocalizations l10n,
    Delegate? delegate,
  ) {
    if (delegate == null || delegate.role != UserRole.delegate) return const [];
    final locale = Localizations.localeOf(context).languageCode;

    // Every chain this person works in (cached memberships), own first.
    final chains = <String>[];
    void addChain(String name) {
      final n = name.trim();
      if (n.isNotEmpty && !chains.contains(n)) chains.add(n);
    }

    addChain(delegate.organizationName);
    try {
      if (di.sl.isRegistered<AuthLocalDataSource>()) {
        for (final d in di.sl<AuthLocalDataSource>().getCachedAllDelegatesData()) {
          if (d.uid == delegate.uid ||
              (delegate.nationalityID.isNotEmpty &&
                  d.nationalityID == delegate.nationalityID)) {
            addChain(d.organizationName);
          }
        }
      }
    } catch (_) {}

    final id = delegate.nationalityID.trim();
    final maskedId = id.length > 4
        ? '${'•' * (id.length - 4)}${id.substring(id.length - 4)}'
        : id;

    Widget tile(IconData icon, String label, String value,
            {Widget? trailing, Key? key}) =>
        ListTile(
          key: key,
          leading: Icon(icon, color: colorScheme.primary),
          title: Text(value, style: theme.textTheme.bodyLarge),
          subtitle: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: trailing,
        );

    final rows = <Widget>[
      if (delegate.delegatePublicId.trim().isNotEmpty)
        tile(
          Symbols.tag_rounded,
          l10n.profileDelegateCode,
          delegate.delegatePublicId.trim(),
          key: const Key('profile_delegate_code'),
          trailing: IconButton(
            tooltip: l10n.profileCopy,
            icon: const Icon(Symbols.content_copy_rounded),
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: delegate.delegatePublicId.trim()),
              );
              if (mounted) showTashilSnackBar(context, l10n.profileCopied);
            },
          ),
        ),
      if (id.isNotEmpty)
        tile(
          Symbols.id_card_rounded,
          l10n.nationalId,
          // A number reads left to right inside Arabic text (F-13).
          Bidi.ltr(_showNationalId ? id : maskedId),
          key: const Key('profile_national_id'),
          trailing: IconButton(
            tooltip: _showNationalId ? l10n.profileHideId : l10n.profileShowId,
            icon: Icon(
              _showNationalId
                  ? Symbols.visibility_off_rounded
                  : Symbols.visibility_rounded,
            ),
            onPressed: () =>
                setState(() => _showNationalId = !_showNationalId),
          ),
        ),
      if (delegate.city.trim().isNotEmpty)
        tile(Symbols.location_city_rounded, l10n.cityLabel, delegate.city.trim()),
      if (chains.isNotEmpty)
        tile(
          Symbols.hub_rounded,
          l10n.profileChains,
          chains.join('، '),
          key: const Key('profile_chains'),
        ),
      tile(
        Symbols.event_available_rounded,
        l10n.joinDate,
        DateFormat('d MMMM y', locale).format(delegate.createdAt),
        key: const Key('profile_join_date'),
      ),
    ];

    return [
      const SizedBox(height: TashilSpacing.xl),
      _sectionTitle(Symbols.work_rounded, l10n.profileWorkInfo),
      Card.filled(
        key: const Key('profile_work_card'),
        margin: EdgeInsets.zero,
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const Divider(height: 1, indent: TashilSpacing.xxl * 2),
              rows[i],
            ],
          ],
        ),
      ),
    ];
  }

  // ─── Security Card ──────────────────────────────────────────────
  Widget _buildSecurityCard(
    ColorScheme colorScheme,
    ThemeData theme,
    AppLocalizations l10n,
    Delegate? delegate,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(Symbols.shield_rounded, l10n.securitySection),
        Card.filled(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              // A settings-style list item (C-23) instead of a wide button.
              ListTile(
                key: const Key('profileChangePasswordButton'),
                leading: Icon(Symbols.lock_reset_rounded, color: colorScheme.primary),
                title: Text(l10n.changePassword),
                // Symbols chevrons mirror in RTL: «forward» points left.
                trailing: Icon(
                  Symbols.chevron_right_rounded,
                  color: colorScheme.onSurfaceVariant,
                ),
                onTap: () => _showChangePasswordSheet(context, delegate),
              ),
              // TAS-207: TOTP enrollment, super admin only.
              Padding(
                padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: TashilSpacing.lg,
                ),
                child: TwoStepVerificationButton(
                  role: delegate?.role,
                  rawRole: _firestoreUserData?['role']?.toString(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── Info Row Widget ────────────────────────────────────────────
  Widget _buildInfoValueText({
    required String value,
    required ThemeData theme,
    required ColorScheme colorScheme,
    String? maestroValueIdentifier,
  }) {
    final text = Text(value, style: theme.textTheme.bodyLarge);
    if (maestroValueIdentifier == null) return text;
    return tashilMaestroDevSemantics(
      identifier: maestroValueIdentifier,
      label: value,
      child: text,
    );
  }

  /// One official list item (C-23): leading icon in primary, the value as
  /// the headline, the label under it, edit as a trailing icon button.
  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    required ColorScheme colorScheme,
    required ThemeData theme,
    VoidCallback? onEdit,
    String? maestroValueIdentifier,
  }) {
    return ListTile(
      leading: Icon(icon, color: colorScheme.primary),
      title: _buildInfoValueText(
        value: value.isEmpty ? '—' : value,
        theme: theme,
        colorScheme: colorScheme,
        maestroValueIdentifier: maestroValueIdentifier,
      ),
      subtitle: Text(
        label,
        style: theme.textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: onEdit == null
          ? null
          : IconButton(
              icon: const Icon(Symbols.edit_rounded),
              tooltip: AppLocalizations.of(context)!.editField(label),
              onPressed: onEdit,
            ),
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
        showTashilSnackBar(context, isName
                  ? AppLocalizations.of(context)!.nameUpdated
                  : (isEmail
                      ? AppLocalizations.of(context)!.emailUpdated
                      : AppLocalizations.of(context)!.phoneUpdated));

        // Trigger auth reload
        context.read<AuthBloc>().add(CheckAutoLoginRequested());
      }
    } catch (e) {
      if (mounted) {
        showTashilSnackBar(context, e is FirebaseFunctionsException
                ? staffContactErrorMessage(e)
                : 'حدث خطأ أثناء التحديث: ${e.toString().replaceAll('Exception: ', '')}');
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

    // TAS-355 (C-28): the sheet's colour, shape and drag handle come from
    // the theme; no second hand-drawn handle.
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        TashilSpacing.xl,
        0,
        TashilSpacing.xl,
        TashilSpacing.xl + bottomInset,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 28, color: colorScheme.primary),
                  const SizedBox(width: TashilSpacing.md),
                  Text(title, style: theme.textTheme.headlineSmall),
                ],
              ),
              const SizedBox(height: TashilSpacing.xl),
              TextFormField(
                controller: _controller,
                keyboardType: isName
                    ? TextInputType.name
                    : (isEmail ? TextInputType.emailAddress : TextInputType.phone),
                // TAS-355 (C-08): outlined like every other field.
                decoration: InputDecoration(
                  labelText: '$label *',
                  prefixIcon: Icon(icon),
                  border: const OutlineInputBorder(),
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
              const SizedBox(height: TashilSpacing.xl),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isLoading ? null : () => Navigator.pop(context),
                      child: Text(AppLocalizations.of(context)!.cancel),
                    ),
                  ),
                  const SizedBox(width: TashilSpacing.lg),
                  Expanded(
                    child: FilledButton(
                      onPressed: _isLoading ? null : _updateInfo,
                      child: _isLoading
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(AppLocalizations.of(context)!.saveAction),
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
        showTashilSnackBar(context, AppLocalizations.of(context)!.passwordChanged);
      }
    } catch (e) {
      if (mounted) {
        showTashilSnackBar(context, '${e.toString().replaceAll('Exception: ', '')}');
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
      // TAS-355 (C-08): outlined; the eye button has a tooltip.
      decoration: InputDecoration(
        labelText: '$label *',
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          tooltip: obscureText
              ? AppLocalizations.of(context)!.showAction
              : AppLocalizations.of(context)!.hideAction,
          icon: Icon(
            obscureText ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          ),
          onPressed: onToggleVisibility,
        ),
        border: const OutlineInputBorder(),
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

      const SizedBox(height: TashilSpacing.lg),

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

      const SizedBox(height: TashilSpacing.lg),

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

    // TAS-355 (C-28): the sheet's colour, shape and drag handle come from
    // the theme; no second hand-drawn handle.
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        TashilSpacing.xl,
        0,
        TashilSpacing.xl,
        TashilSpacing.xl + bottomInset,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock_reset_rounded, size: 28, color: colorScheme.primary),
                  const SizedBox(width: TashilSpacing.md),
                  Text(
                    AppLocalizations.of(context)!.changePassword,
                    style: theme.textTheme.headlineSmall,
                  ),
                ],
              ),
              const SizedBox(height: TashilSpacing.xl),

              ..._buildFields(context, colorScheme),

              const SizedBox(height: TashilSpacing.xl),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isLoading ? null : () => Navigator.pop(context),
                      child: Text(AppLocalizations.of(context)!.cancel),
                    ),
                  ),
                  const SizedBox(width: TashilSpacing.lg),
                  Expanded(
                    child: FilledButton(
                      onPressed: _isLoading ? null : _changePassword,
                      child: _isLoading
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(AppLocalizations.of(context)!.saveAction),
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

