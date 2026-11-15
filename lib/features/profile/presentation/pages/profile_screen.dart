import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:delegate_app/core/security/delegate_status_policy.dart';
import 'package:delegate_app/core/widgets/app_snack_bar.dart';
import 'package:delegate_app/core/widgets/app_avatar.dart';
import 'package:delegate_app/features/admin/presentation/bloc/admin_delegates_bloc.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/profile/presentation/bloc/profile_bloc.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:delegate_app/injection_container.dart' as di;
import 'package:delegate_app/features/profile/data/datasources/supervisor_delegate_doc_reupload_remote.dart';
import 'package:delegate_app/features/profile/presentation/utils/document_review.dart';

class ProfileScreen extends StatefulWidget {
  final Delegate delegate;
  final bool showBackButton;
  final int initialTabIndex;

  const ProfileScreen({
    super.key,
    required this.delegate,
    this.showBackButton = false,
    this.initialTabIndex = 0,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  @override
  void initState() {
    super.initState();
    // Load full delegate profile from Firebase if ProfileBloc is available
    Future.microtask(() {
      if (mounted) {
        try {
          context.read<ProfileBloc>().add(
            LoadProfile(
              uid: widget.delegate.uid,
              organizationUID: widget.delegate.organizationUID,
              companyUID: widget.delegate.companyUID,
            ),
          );
        } catch (_) {}
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget profileContent = BlocBuilder<ProfileBloc, ProfileState>(
      builder: (context, state) {
        // Use loaded delegate if available, otherwise use passed delegate
        final delegate = state is ProfileLoaded
            ? state.delegate
            : widget.delegate;

        return DefaultTabController(
          length: 3,
          initialIndex: widget.initialTabIndex,
          child: _ProfileBody(
            delegate: delegate,
            showBackButton: widget.showBackButton,
            isLoading: state is ProfileLoading,
            error: state is ProfileError ? state.message : null,
          ),
        );
      },
    );

    // Ensure ProfileBloc is present; if not, wrap with a local provider
    try {
      BlocProvider.of<ProfileBloc>(context);
      return profileContent;
    } catch (_) {
      return BlocProvider(
        create: (_) => di.sl<ProfileBloc>()
          ..add(
            LoadProfile(
              uid: widget.delegate.uid,
              organizationUID: widget.delegate.organizationUID,
              companyUID: widget.delegate.companyUID,
            ),
          ),
        child: profileContent,
      );
    }
  }
}

class _ProfileBody extends StatelessWidget {
  final Delegate delegate;
  final bool showBackButton;
  final bool isLoading;
  final String? error;

  const _ProfileBody({
    required this.delegate,
    this.showBackButton = false,
    this.isLoading = false,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Show error state if there's an error
    if (error != null) {
      return Scaffold(
        appBar: showBackButton
            ? AppBar(
                title: Text(delegate.fullName),
                backgroundColor: colorScheme.surface,
                scrolledUnderElevation: 0,
              )
            : null,
        backgroundColor: colorScheme.surface,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: colorScheme.error),
              const SizedBox(height: 16),
              Text(
                'خطأ في تحميل البيانات',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colorScheme.error,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                error!,
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

    return Scaffold(
      appBar: showBackButton
          ? AppBar(
              title: Text(delegate.fullName),
              backgroundColor: colorScheme.surface,
              scrolledUnderElevation: 0,
              actions: [
                if (_canDeleteDelegate(context, delegate))
                  IconButton(
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      color: colorScheme.error,
                    ),
                    tooltip: l10n.delete,
                    onPressed: () => _confirmAndDeleteDelegate(context, l10n),
                  ),
              ],
            )
          : null,
      backgroundColor: colorScheme.surface,
      body: isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    'جاري تحميل البيانات...',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
          : NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) {
                return [
                  SliverToBoxAdapter(
                    child: _buildProfileHeader(context, colorScheme, l10n),
                  ),
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _TabBarDelegate(
                      TabBar(
                        labelColor: colorScheme.primary,
                        unselectedLabelColor: colorScheme.onSurfaceVariant,
                        indicatorColor: colorScheme.primary,
                        indicatorWeight: 3,
                        labelStyle: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        tabs: [
                          Tab(text: l10n.personalInformation),
                          Tab(text: l10n.documents),
                          Tab(text: l10n.requestHistory),
                        ],
                      ),
                    ),
                  ),
                ];
              },
              body: TabBarView(
                children: [
                  _buildPersonalInfoTab(context, l10n),
                  _buildDocumentsTab(context, l10n),
                  _buildRequestHistoryTab(context, l10n),
                ],
              ),
            ),
    );
  }

  // ─── Profile Header ─────────────────────────────────────────────
  Widget _buildProfileHeader(
    BuildContext context,
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    return Container(
      color: colorScheme.surface,
      padding: const EdgeInsetsDirectional.fromSTEB(20, 48, 20, 24),
      child: Column(
        children: [
          _buildProfileAvatar(colorScheme),
          const SizedBox(height: 16),
          Text(
            delegate.fullName,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            '${l10n.delegateId}: ${delegate.delegatePublicId}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              delegate.position.name.toUpperCase(),
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSecondaryContainer,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileAvatar(ColorScheme colorScheme) {
    final personalPhotoUrl = _getPersonalPhotoUrl();
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: colorScheme.outlineVariant, width: 2),
      ),
      child: AppAvatar(
        imageUrl: personalPhotoUrl,
        fallbackText: delegate.firstName,
        radius: 48,
        backgroundColor: colorScheme.surfaceContainerHighest,
        foregroundColor: colorScheme.onSurfaceVariant,
      ),
    );
  }

  String? _getPersonalPhotoUrl() {
    try {
      final photoDoc = delegate.documents.firstWhere(
        (doc) =>
            doc.documentKey == DocumentKey.personalPhoto &&
            doc.documentURL.isNotEmpty,
      );
      return photoDoc.documentURL;
    } catch (_) {
      return null;
    }
  }

  // ─── Tab 1: Personal Information ────────────────────────────────
  Widget _buildPersonalInfoTab(BuildContext context, AppLocalizations l10n) {
    final dateFormat = DateFormat('yyyy/MM/dd');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Personal details card
        _SectionCard(
          title: l10n.personalInformation,
          icon: Icons.person_outline_rounded,
          children: [
            _InfoRow(
              icon: Icons.badge_outlined,
              label: l10n.fullName,
              value: delegate.fullName,
            ),
            _InfoRow(
              icon: Icons.credit_card_outlined,
              label: l10n.nationalId,
              value: delegate.nationalityID,
            ),
            _InfoRow(
              icon: Icons.family_restroom_rounded,
              label: l10n.motherName,
              value: delegate.motherName,
            ),
            _InfoRow(
              icon: Icons.wc_outlined,
              label: l10n.gender,
              value: delegate.gender == DelegateGender.male
                  ? l10n.male
                  : l10n.female,
            ),
            _InfoRow(
              icon: Icons.phone_outlined,
              label: l10n.phoneNumber,
              value: delegate.phoneNumber,
            ),
            _InfoRow(
              icon: Icons.cake_outlined,
              label: l10n.birthDate,
              value: dateFormat.format(delegate.birthDate),
            ),
            _InfoRow(
              icon: Icons.location_city_outlined,
              label: l10n.cityLabel,
              value: delegate.city,
              showDivider: false,
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Employment Details Card
        _SectionCard(
          title: l10n.employmentDetails,
          icon: Icons.work_outline_rounded,
          children: [
            _InfoRow(
              icon: Icons.corporate_fare_outlined,
              label: l10n.organizationLabel,
              value: delegate.organizationName.isNotEmpty
                  ? delegate.organizationName
                  : delegate.organizationUID,
            ),
            _InfoRow(
              icon: Icons.store_mall_directory_outlined,
              label: l10n.companyLabel,
              value: delegate.companyName.isNotEmpty
                  ? delegate.companyName
                  : delegate.companyUID,
            ),
            _InfoRow(
              icon: Icons.date_range_outlined,
              label: l10n.joinDate,
              value: dateFormat.format(delegate.createdAt),
            ),
            if (delegate.statusReason != null &&
                delegate.statusReason!.isNotEmpty)
              _InfoRow(
                icon: Icons.info_outline,
                label: l10n.statusReason,
                value: delegate.statusReason!,
              ),
            _InfoRow(
              icon: delegate.isProfileComplete
                  ? Icons.check_circle_outline
                  : Icons.warning_amber_rounded,
              label: 'Profile Status',
              value: delegate.isProfileComplete
                  ? l10n.profileComplete
                  : l10n.profileIncomplete,
              showDivider: false,
            ),
          ],
        ),
        if (_canDeleteDelegate(context, delegate)) ...[
          const SizedBox(height: 20),
          _buildDeleteDelegateSection(context, l10n),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  bool _isFathallaDelegate(Delegate delegate) {
    final orgName = delegate.organizationName.toLowerCase().trim();
    final orgUid = delegate.organizationUID.toLowerCase().trim();
    return orgName.contains('fathalla') ||
        orgName.contains('فتح الله') ||
        orgName.contains('فتح_الله') ||
        orgUid.contains('fathalla') ||
        orgUid.contains('فتح الله') ||
        orgUid.contains('فتح_الله');
  }

  bool _canDeleteDelegate(BuildContext context, Delegate targetDelegate) {
    // 1. A delegate can NEVER delete themselves or any other user.
    // 2. Only Admins / Super Admins / Org Admins can delete a delegate (and never delete themselves).
    try {
      final authState = context.read<AuthBloc>().state;
      if (authState is AuthAuthenticated) {
        final currentUser = authState.delegate;
        // A user can never delete their own account/profile
        if (currentUser.uid == targetDelegate.uid) {
          return false;
        }
        // Only administrative roles have delete permissions
        final isAdmin = currentUser.role == UserRole.superAdmin ||
            currentUser.role == UserRole.admin ||
            currentUser.role == UserRole.organizationAdmin;
        if (!isAdmin) {
          return false;
        }
      } else {
        return false;
      }
    } catch (_) {
      return false;
    }

    // Fathalla delegates cannot be deleted
    if (_isFathallaDelegate(targetDelegate)) {
      return false;
    }

    return true;
  }

  Widget _buildDeleteDelegateSection(
    BuildContext context,
    AppLocalizations l10n,
  ) {
    final theme = Theme.of(context);
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final buttonLabel = isArabic ? 'حذف المندوب' : 'Delete Delegate';

    return Card(
      elevation: 0,
      color: Colors.red.withValues(alpha: 0.04),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Colors.red.withValues(alpha: 0.35),
          width: 1.2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.delete_forever_rounded,
                    color: Colors.red,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        buttonLabel,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isArabic
                            ? 'حذف هذا المندوب وبياناته نهائياً من المنظومة'
                            : 'Permanently delete this delegate from the system',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => _confirmAndDeleteDelegate(context, l10n),
              icon: const Icon(Icons.delete_outline_rounded, size: 20),
              label: Text(
                buttonLabel,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmAndDeleteDelegate(
    BuildContext context,
    AppLocalizations l10n,
  ) async {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    if (!_canDeleteDelegate(context, delegate)) {
      AppSnackBar.showError(
        context,
        isArabic
            ? 'غير مصرح لك بحذف هذا الحساب'
            : 'You are not authorized to delete this account',
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.warning_amber_rounded,
                color: Colors.red,
                size: 26,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                isArabic ? 'حذف المندوب' : 'Delete Delegate',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isArabic
                  ? 'هل أنت متأكد من رغبتك في حذف المندوب "${delegate.fullName}"؟'
                  : 'Are you sure you want to permanently delete delegate "${delegate.fullName}"?',
              style: const TextStyle(
                fontSize: 14.5,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              isArabic
                  ? '⚠️ سيتم حذف ملف المندوب ومستنداته نهائياً من قاعدة البيانات ولا يمكن التراجع عن هذه العملية.'
                  : '⚠️ This will permanently delete the delegate and all associated documents from the database. This action cannot be undone.',
              style: TextStyle(
                fontSize: 12.5,
                color: Theme.of(ctx).colorScheme.error,
                height: 1.3,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(isArabic ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.delete_forever_rounded, size: 18),
            label: Text(isArabic ? 'تأكيد الحذف' : 'Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!context.mounted) return;

    // Show loading progress dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Center(
        child: Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: Colors.red),
                const SizedBox(height: 18),
                Text(
                  isArabic ? 'جاري حذف المندوب...' : 'Deleting delegate...',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final firestore = FirebaseFirestore.instance;

      // 1. Delete from organizations subcollection
      if (delegate.companyUID.isNotEmpty) {
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
            await delRef.delete();
          }
        }
      }

      // 2. CollectionGroup query deletion to ensure no orphan doc exists
      try {
        final groupQuery = await firestore
            .collectionGroup('delegates')
            .where('uid', isEqualTo: delegate.uid)
            .get();
        for (final doc in groupQuery.docs) {
          await doc.reference.delete();
        }
      } catch (_) {}

      // 3. Delete from delegate_requests if exists
      try {
        final reqRef =
            firestore.collection('delegate_requests').doc(delegate.uid);
        final reqSnap = await reqRef.get();
        if (reqSnap.exists) {
          await reqRef.delete();
        }
        // Company is the tenant: company staff list by companyUID (any chain).
        // Org-admin lists by organizationUID. Never run an unscoped list query.
        Query<Map<String, dynamic>>? cleanupRequestsQuery() {
          Query<Map<String, dynamic>> q =
              firestore.collection('delegate_requests');
          Delegate? me;
          try {
            final state = context.read<AuthBloc>().state;
            if (state is AuthAuthenticated) me = state.delegate;
          } catch (_) {}
          if (me != null &&
              (me.role == UserRole.superAdmin ||
                  me.role == UserRole.technicalSupport)) {
            if (delegate.companyUID.isNotEmpty) {
              return q.where('companyUID', isEqualTo: delegate.companyUID);
            }
            return q;
          }
          if (me != null && me.role == UserRole.organizationAdmin) {
            final org = me.organizationUID.isNotEmpty
                ? me.organizationUID
                : delegate.organizationUID;
            if (org.isEmpty) return null;
            return q.where('organizationUID', isEqualTo: org);
          }
          if (delegate.companyUID.isEmpty) return null;
          return q.where('companyUID', isEqualTo: delegate.companyUID);
        }

        final cleanupQuery = cleanupRequestsQuery();
        if (cleanupQuery != null) {
          if (delegate.nationalityID.isNotEmpty) {
            final reqById = await cleanupQuery
                .where('nationalId', isEqualTo: delegate.nationalityID.trim())
                .get();
            for (final doc in reqById.docs) {
              await doc.reference.delete();
            }
          }
          if (delegate.phoneNumber.isNotEmpty) {
            final cleanPhone =
                delegate.phoneNumber.replaceAll(RegExp(r'\s+'), '').trim();
            final reqByPhone = await cleanupQuery
                .where('phoneNumber', isEqualTo: cleanPhone)
                .get();
            for (final doc in reqByPhone.docs) {
              await doc.reference.delete();
            }
          }
        }
      } catch (_) {}

      // 4. Delete associated notifications
      try {
        final notifs = await firestore
            .collection('notifications')
            .where('requestId', isEqualTo: delegate.uid)
            .get();
        for (final n in notifs.docs) {
          await n.reference.delete();
        }
      } catch (_) {}

      // 5. Delete from users collection if role is delegate/promoter
      try {
        final userDoc = firestore.collection('users').doc(delegate.uid);
        final uSnap = await userDoc.get();
        if (uSnap.exists) {
          final role = uSnap.data()?['role']?.toString().toLowerCase();
          if (role == 'delegate' || role == 'promoter' || role == null) {
            await userDoc.delete();
          }
        }
      } catch (_) {}

      // 6. Delete storage assets if any
      try {
        final storage = FirebaseStorage.instance;
        final folderRef = storage.ref('delegate_documents/${delegate.uid}');
        final listRes = await folderRef.listAll();
        for (final item in listRes.items) {
          await item.delete();
        }
      } catch (_) {}

      // 7. Clear delegates cache
      AdminDelegatesBloc.clearCache();

      if (context.mounted) {
        Navigator.pop(context); // Dismiss progress dialog
        AppSnackBar.showSuccess(
          context,
          isArabic ? '✅ تم حذف المندوب بنجاح' : '✅ Delegate deleted successfully',
        );
        Navigator.pop(context, true); // Return to previous screen with true
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // Dismiss progress dialog
        AppSnackBar.showError(
          context,
          isArabic ? 'فشل حذف المندوب: $e' : 'Failed to delete delegate: $e',
        );
      }
    }
  }

  // ─── Tab 2: Documents ───────────────────────────────────────────
  Widget _buildDocumentsTab(BuildContext context, AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    final displayDocs = _getDisplayDocuments(l10n);

    if (displayDocs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.description_outlined,
              size: 80,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.noDocumentsUploaded,
              style: TextStyle(
                fontSize: 16,
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 0.58,
      ),
      itemCount: displayDocs.length,
      itemBuilder: (context, index) {
        final canReview = _docApproverUid(context) != null;
        final item = displayDocs[index];
        return _DocumentCard(
          item: item,
          l10n: l10n,
          onEdit: () => _handleEditDocument(context, item),
          onReview: canReview && item.status == DocumentStatus.pending
              ? (approve) => _reviewDocument(context, item, approve)
              : null,
        );
      },
    );
  }

  List<_DisplayDocument> _getDisplayDocuments(AppLocalizations l10n) {
    final List<_DisplayDocument> list = [];

    for (final doc in delegate.documents) {
      if (doc.documentKey == DocumentKey.personalPhoto) {
        list.add(
          _DisplayDocument(
            id: 'personalPhoto',
            title: l10n.personalPhoto,
            imageUrl: doc.documentURL,
            status: doc.documentStatus,
            docType: 'personalPhoto',
            uploadedAt: doc.uploadedAt,
            rejectionReason: doc.rejectionReason,
            defaultIcon: Icons.photo_camera_outlined,
          ),
        );
      } else if (doc.documentKey == DocumentKey.nationalityId) {
        list.add(
          _DisplayDocument(
            id: 'nationalIdFront',
            title: 'بطاقة الرقم القومي (الوجه)',
            imageUrl: doc.documentURL,
            status: doc.documentStatus,
            docType: 'nationalIdFront',
            uploadedAt: doc.uploadedAt,
            rejectionReason: doc.rejectionReason,
            defaultIcon: Icons.credit_card_outlined,
          ),
        );
        if (doc.secondaryURL != null && doc.secondaryURL!.isNotEmpty) {
          list.add(
            _DisplayDocument(
              id: 'nationalIdBack',
              title: 'بطاقة الرقم القومي (الظهر)',
              imageUrl: doc.secondaryURL!,
              status: doc.documentStatus,
              docType: 'nationalIdBack',
              uploadedAt: doc.uploadedAt,
              rejectionReason: doc.rejectionReason,
              defaultIcon: Icons.credit_card_outlined,
            ),
          );
        }
      } else {
        list.add(
          _DisplayDocument(
            id: doc.documentKey.name,
            title: _getDocumentTitleHelper(doc.documentKey, l10n),
            imageUrl: doc.documentURL,
            status: doc.documentStatus,
            docType: doc.documentKey.name,
            uploadedAt: doc.uploadedAt,
            rejectionReason: doc.rejectionReason,
            defaultIcon: _getDocumentIconHelper(doc.documentKey),
          ),
        );
      }
    }
    return list;
  }

  /// uid when the viewer may approve documents: super-admin or technical
  /// support only (Mohamed 2026-11-15). Supervisors re-upload as pending;
  /// SA/tech approve.
  String? _docApproverUid(BuildContext context) {
    try {
      final state = context.read<AuthBloc>().state;
      if (state is! AuthAuthenticated) return null;
      final me = state.delegate;
      if (me.uid == delegate.uid) return null;
      if (me.role == UserRole.superAdmin ||
          me.role == UserRole.technicalSupport) {
        return me.uid;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _reviewDocument(
    BuildContext context,
    _DisplayDocument item,
    bool approve,
  ) async {
    final reviewerUid = _docApproverUid(context);
    if (reviewerUid == null) return;
    String? reason;
    if (!approve) {
      final controller = TextEditingController();
      reason = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('سبب الرفض'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('رفض'),
            ),
          ],
        ),
      );
      if (reason == null || reason.isEmpty) return;
    }
    try {
      final firestore = FirebaseFirestore.instance;
      final refs = <DocumentReference<Map<String, dynamic>>>[];
      if (delegate.companyUID.isNotEmpty) {
        final orgsSnap = await firestore.collection('organizations').get();
        for (final orgDoc in orgsSnap.docs) {
          refs.add(firestore
              .collection('organizations')
              .doc(orgDoc.id)
              .collection('companies')
              .doc(delegate.companyUID)
              .collection('delegates')
              .doc(delegate.uid));
        }
      }
      refs.add(firestore.collection('delegate_requests').doc(delegate.uid));
      var updated = 0;
      for (final ref in refs) {
        try {
          final changed = await firestore.runTransaction<bool>((tx) async {
            final snap = await tx.get(ref);
            if (!snap.exists) return false;
            final docs = reviewDocumentEntry(
              snap.data()?['documents'],
              docType: item.docType,
              approve: approve,
              reviewerUid: reviewerUid,
              rejectionReason: reason,
            );
            if (docs == null) return false;
            tx.update(ref, {
              'documents': docs,
              'updatedAt': FieldValue.serverTimestamp(),
            });
            return true;
          });
          if (changed) updated++;
        } catch (_) {
          if (ref.parent.id != 'delegate_requests') rethrow;
        }
      }
      if (!context.mounted) return;
      if (updated == 0) {
        AppSnackBar.showError(context, 'لم يتم العثور على المستند');
        return;
      }
      AppSnackBar.showSuccess(
        context,
        approve ? 'تم اعتماد ${item.title}' : 'تم رفض ${item.title}',
      );
      context.read<ProfileBloc>().add(
        LoadProfile(
          uid: delegate.uid,
          organizationUID: delegate.organizationUID,
          companyUID: delegate.companyUID,
        ),
      );
    } catch (e) {
      if (context.mounted) {
        AppSnackBar.showError(context, 'فشل تحديث حالة المستند: $e');
      }
    }
  }

  Future<void> _handleEditDocument(
    BuildContext context,
    _DisplayDocument item,
  ) async {
    final approverUid = _docApproverUid(context);
    final picker = ImagePicker();
    final ImageSource? source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'تحديث ${item.title}',
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.camera_alt_rounded,
                    color: Theme.of(ctx).colorScheme.primary,
                  ),
                ),
                title: const Text('التقاط صورة بالكاميرا'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.secondaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.photo_library_rounded,
                    color: Theme.of(ctx).colorScheme.secondary,
                  ),
                ),
                title: const Text('اختيار صورة من المعرض'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );

    if (source == null) return;

    final picked = await picker.pickImage(
      source: source,
      imageQuality: 85,
    );
    if (picked == null) return;

    if (!context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('جاري رفع وتحديث المستند...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final file = File(picked.path);

      final firestore = FirebaseFirestore.instance;

      final authState = context.read<AuthBloc>().state;
      final viewer = authState is AuthAuthenticated ? authState.delegate : null;
      final supervisorPendingReupload = shouldSupervisorMarkDelegatePendingOnDocReplace(
        target: delegate,
        viewerRole: viewer?.role,
        viewerUid: viewer?.uid ?? '',
        viewerCompanyUID: viewer?.companyUID,
        viewerIsDocApprover: approverUid != null,
      );

      if (supervisorPendingReupload) {
        await SupervisorDelegateDocReuploadRemote().replaceWithFile(
          uid: delegate.uid,
          organizationUID: delegate.organizationUID,
          companyUID: delegate.companyUID,
          docType: item.docType,
          file: file,
        );
        if (context.mounted) {
          Navigator.pop(context);
          AppSnackBar.showSuccess(context, 'تم تحديث ${item.title} وسيُراجع من الإدارة.');
          context.read<ProfileBloc>().add(
            LoadProfile(
              uid: delegate.uid,
              organizationUID: delegate.organizationUID,
              companyUID: delegate.companyUID,
            ),
          );
        }
        return;
      }

      if (approverUid != null) {
        await PrivilegedDelegateDocReuploadRemote().replaceWithFile(
          uid: delegate.uid,
          organizationUID: delegate.organizationUID,
          companyUID: delegate.companyUID,
          docType: item.docType,
          file: file,
        );
        if (context.mounted) {
          Navigator.pop(context);
          AppSnackBar.showSuccess(context, 'تم تحديث ${item.title} بنجاح!');
          context.read<ProfileBloc>().add(
            LoadProfile(
              uid: delegate.uid,
              organizationUID: delegate.organizationUID,
              companyUID: delegate.companyUID,
            ),
          );
        }
        return;
      }

      final storagePath = delegateDocumentStoragePath(
        delegateUid: delegate.uid,
        docType: item.docType,
      );
      final newUrl = await uploadDelegateDocumentFile(
        folderId: delegate.uid,
        companyUID: delegate.companyUID,
        storagePath: storagePath,
        file: file,
      );

      final Map<String, dynamic> updateFields = {
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (item.docType == 'personalPhoto') {
        updateFields['profileImageUrl'] = newUrl;
        updateFields['personalPhotoURL'] = newUrl;
      } else if (item.docType == 'nationalIdFront') {
        updateFields['nationalIdFrontUrl'] = newUrl;
      } else if (item.docType == 'nationalIdBack') {
        updateFields['nationalIdBackUrl'] = newUrl;
      } else if (item.docType == 'paymentReceipt') {
        updateFields['receiptImageUrl'] = newUrl;
      }

      // Docs-pending (Mohamed 2026-11-04): a delegate's own re-upload is
      // written as 'pending'; privileged staff use the server callable.

      // Update in all organizations where this company & delegate reside
      if (delegate.companyUID.isNotEmpty) {
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
            await delRef.set({
              ...updateFields,
              'documents': mergeReuploadedDocument(
                check.data()?['documents'],
                docType: item.docType,
                newUrl: newUrl,
                approverUid: null,
              ),
            }, SetOptions(merge: true));
          }
        }
      }

      if (item.docType == 'personalPhoto') {
        await firestore.collection('users').doc(delegate.uid).set({
          'photoURL': newUrl,
          'profileImageUrl': newUrl,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      try {
        final reqRef =
            firestore.collection('delegate_requests').doc(delegate.uid);
        final reqSnap = await reqRef.get();
        if (reqSnap.exists) {
          await reqRef.set({
            ...updateFields,
            'documents': mergeReuploadedDocument(
              reqSnap.data()?['documents'],
              docType: item.docType,
              newUrl: newUrl,
              approverUid: null,
            ),
          }, SetOptions(merge: true));
        }
      } catch (_) {}

      if (context.mounted) {
        Navigator.pop(context); // dismiss progress dialog
        AppSnackBar.showSuccess(
          context,
          'تم رفع ${item.title}، بانتظار مراجعة المشرف',
        );
        context.read<ProfileBloc>().add(
          LoadProfile(
            uid: delegate.uid,
            organizationUID: delegate.organizationUID,
            companyUID: delegate.companyUID,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // dismiss progress dialog
        AppSnackBar.showError(
          context,
          supervisorDocReplaceErrorMessage(e),
        );
      }
    }
  }

  // ─── Tab 3: Request History ─────────────────────────────────────
  Widget _buildRequestHistoryTab(BuildContext context, AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history_outlined,
            size: 80,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            l10n.noRequestsYet,
            style: TextStyle(
              fontSize: 16,
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Section Card Widget ──────────────────────────────────────────
class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: colorScheme.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}

// ─── Info Row Widget ──────────────────────────────────────────────
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool showDivider;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
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
                  color: colorScheme.primaryContainer,
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
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (showDivider) Divider(height: 1, color: colorScheme.outlineVariant),
      ],
    );
  }
}

class _DisplayDocument {
  final String id;
  final String title;
  final String imageUrl;
  final DocumentStatus status;
  final String docType;
  final DateTime? uploadedAt;
  final String? rejectionReason;
  final IconData defaultIcon;

  const _DisplayDocument({
    required this.id,
    required this.title,
    required this.imageUrl,
    required this.status,
    required this.docType,
    this.uploadedAt,
    this.rejectionReason,
    this.defaultIcon = Icons.description_outlined,
  });
}

String _getDocumentTitleHelper(DocumentKey key, AppLocalizations l10n) {
  switch (key) {
    case DocumentKey.personalPhoto:
      return l10n.personalPhoto;
    case DocumentKey.nationalityId:
      return l10n.nationalId;
    case DocumentKey.authorizationLetter:
      return l10n.authorizationLetter;
    case DocumentKey.insuranceLetter:
      return l10n.insuranceLetter;
    case DocumentKey.healthCertificate:
      return l10n.healthCertificate;
    case DocumentKey.paymentReceipt:
      return l10n.paymentReceipt;
    case DocumentKey.electronicPaymentReceipt:
      return l10n.electronicPaymentReceipt;
  }
}

IconData _getDocumentIconHelper(DocumentKey key) {
  switch (key) {
    case DocumentKey.personalPhoto:
      return Icons.photo_camera_outlined;
    case DocumentKey.nationalityId:
      return Icons.credit_card_outlined;
    case DocumentKey.authorizationLetter:
      return Icons.description_outlined;
    case DocumentKey.insuranceLetter:
      return Icons.shield_outlined;
    case DocumentKey.healthCertificate:
      return Icons.local_hospital_outlined;
    case DocumentKey.paymentReceipt:
      return Icons.receipt_long_outlined;
    case DocumentKey.electronicPaymentReceipt:
      return Icons.receipt_long_rounded;
  }
}

Color _getStatusColorHelper(DocumentStatus status, ColorScheme colorScheme) {
  switch (status) {
    case DocumentStatus.approved:
      return colorScheme.tertiary;
    case DocumentStatus.rejected:
      return colorScheme.error;
    case DocumentStatus.pending:
      return colorScheme.secondary;
    case DocumentStatus.notProvided:
      return colorScheme.outline;
  }
}

IconData _getStatusIconHelper(DocumentStatus status) {
  switch (status) {
    case DocumentStatus.approved:
      return Icons.check_circle;
    case DocumentStatus.rejected:
      return Icons.cancel;
    case DocumentStatus.pending:
      return Icons.schedule;
    case DocumentStatus.notProvided:
      return Icons.remove_circle_outline;
  }
}

String _getStatusTextHelper(DocumentStatus status, AppLocalizations l10n) {
  switch (status) {
    case DocumentStatus.approved:
      return l10n.approvedStatus;
    case DocumentStatus.rejected:
      return l10n.rejectedStatus;
    case DocumentStatus.pending:
      return l10n.pendingStatus;
    case DocumentStatus.notProvided:
      return l10n.notProvidedStatus;
  }
}

// ─── Document Card Widget ─────────────────────────────────────────
class _DocumentCard extends StatelessWidget {
  final _DisplayDocument item;
  final AppLocalizations l10n;
  final VoidCallback onEdit;
  final void Function(bool approve)? onReview;

  const _DocumentCard({
    required this.item,
    required this.l10n,
    required this.onEdit,
    this.onReview,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final Color statusColor = _getStatusColorHelper(item.status, colorScheme);
    final IconData statusIcon = _getStatusIconHelper(item.status);
    final String statusText = _getStatusTextHelper(item.status, l10n);
    final bool hasImage = item.imageUrl.isNotEmpty;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Image Thumbnail with Fullscreen Tap ──
          Expanded(
            flex: 3,
            child: InkWell(
              onTap: hasImage
                  ? () =>
                      _showFullScreenImage(context, item.title, item.imageUrl)
                  : null,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  hasImage
                      ? CachedNetworkImage(
                          imageUrl: item.imageUrl,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            color: colorScheme.surfaceContainerHighest,
                            child: const Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                ),
                              ),
                            ),
                          ),
                          errorWidget: (context, url, error) => Container(
                            color: colorScheme.surfaceContainerHighest,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.broken_image_outlined,
                                  size: 32,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'فشل التحميل',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : Container(
                          color: colorScheme.surfaceContainerHighest,
                          child: Icon(
                            item.defaultIcon,
                            size: 40,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                  // Status badge overlay
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: statusColor.withValues(alpha: 0.4),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(statusIcon, size: 10, color: Colors.white),
                          const SizedBox(width: 3),
                          Text(
                            statusText,
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Zoom icon overlay
                  if (hasImage)
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(
                          Icons.zoom_in_rounded,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // ── Bottom Info & Edit Button ──
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    item.title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (item.uploadedAt != null)
                    Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 10,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            DateFormat('yyyy/MM/dd').format(item.uploadedAt!),
                            style: TextStyle(
                              fontSize: 9,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  if (onReview != null)
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 26,
                            child: FilledButton(
                              key: const Key('doc_approve_button'),
                              style: FilledButton.styleFrom(
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () => onReview!(true),
                              child: const Text('اعتماد',
                                  style: TextStyle(fontSize: 10)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: SizedBox(
                            height: 26,
                            child: OutlinedButton(
                              key: const Key('doc_reject_button'),
                              style: OutlinedButton.styleFrom(
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                                foregroundColor: colorScheme.error,
                              ),
                              onPressed: () => onReview!(false),
                              child: const Text('رفض',
                                  style: TextStyle(fontSize: 10)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  SizedBox(
                    width: double.infinity,
                    height: 28,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_rounded, size: 13),
                      label: const Text(
                        'تعديل / استبدال',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showFullScreenImage(BuildContext context, String title, String url) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Theme.of(
          context,
        ).colorScheme.inverseSurface.withValues(alpha: 0.87),
        pageBuilder: (context, animation, secondaryAnimation) {
          return _FullScreenImageViewer(imageUrl: url, title: title);
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }
}

// ─── Full-Screen Image Viewer ─────────────────────────────────────
class _FullScreenImageViewer extends StatelessWidget {
  final String imageUrl;
  final String title;

  const _FullScreenImageViewer({required this.imageUrl, required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surface.withValues(alpha: 0),
      appBar: AppBar(
        backgroundColor: colorScheme.surface.withValues(alpha: 0),
        elevation: 0,
        title: Text(
          title,
          style: TextStyle(
            color: colorScheme.onInverseSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: IconButton(
          icon: Icon(
            Icons.close_rounded,
            color: colorScheme.onInverseSurface,
            size: 28,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.open_in_new_rounded,
              color: colorScheme.onInverseSurface,
            ),
            tooltip: 'Open in browser',
            onPressed: () async {
              final uri = Uri.parse(imageUrl);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.contain,
            placeholder: (context, url) => Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(
                  colorScheme.onInverseSurface,
                ),
              ),
            ),
            errorWidget: (context, url, error) => Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.broken_image_outlined,
                  size: 64,
                  color: colorScheme.onInverseSurface.withValues(alpha: 0.54),
                ),
                const SizedBox(height: 16),
                Text(
                  'فشل تحميل الصورة',
                  style: TextStyle(
                    color: colorScheme.onInverseSurface.withValues(alpha: 0.54),
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;

  _TabBarDelegate(this.tabBar);

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: tabBar,
    );
  }

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  bool shouldRebuild(covariant _TabBarDelegate oldDelegate) => false;
}
