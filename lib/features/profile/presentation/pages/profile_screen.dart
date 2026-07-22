import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/profile/presentation/bloc/profile_bloc.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

class ProfileScreen extends StatefulWidget {
  final Delegate delegate;
  final bool showBackButton;

  const ProfileScreen({
    super.key,
    required this.delegate,
    this.showBackButton = false,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  @override
  void initState() {
    super.initState();
    // Load full delegate profile from Firebase
    Future.microtask(() {
      if (mounted) {
        context.read<ProfileBloc>().add(
          LoadProfile(
            uid: widget.delegate.uid,
            organizationUID: widget.delegate.organizationUID,
            companyUID: widget.delegate.companyUID,
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProfileBloc, ProfileState>(
      builder: (context, state) {
        // Use loaded delegate if available, otherwise use passed delegate
        final delegate = state is ProfileLoaded
            ? state.delegate
            : widget.delegate;

        return DefaultTabController(
          length: 3,
          child: _ProfileBody(
            delegate: delegate,
            showBackButton: widget.showBackButton,
            isLoading: state is ProfileLoading,
            error: state is ProfileError ? state.message : null,
          ),
        );
      },
    );
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
      child: personalPhotoUrl != null
          ? CircleAvatar(
              radius: 48,
              backgroundColor: colorScheme.surfaceContainerHighest,
              backgroundImage: CachedNetworkImageProvider(personalPhotoUrl),
            )
          : CircleAvatar(
              radius: 48,
              backgroundColor: colorScheme.surfaceContainerHighest,
              child: Icon(
                Icons.person,
                size: 50,
                color: colorScheme.onSurfaceVariant,
              ),
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
      ],
    );
  }

  // ─── Tab 2: Documents ───────────────────────────────────────────
  Widget _buildDocumentsTab(BuildContext context, AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    if (delegate.documents.isEmpty) {
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
        childAspectRatio: 0.72,
      ),
      itemCount: delegate.documents.length,
      itemBuilder: (context, index) {
        return _DocumentCard(document: delegate.documents[index], l10n: l10n);
      },
    );
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

// ─── Document Card Widget ─────────────────────────────────────────
class _DocumentCard extends StatelessWidget {
  final DelegateDocument document;
  final AppLocalizations l10n;

  const _DocumentCard({required this.document, required this.l10n});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final String title = _getDocumentTitle(document.documentKey, l10n);
    final Color statusColor = _getStatusColor(
      document.documentStatus,
      colorScheme,
    );
    final IconData statusIcon = _getStatusIcon(document.documentStatus);
    final String statusText = _getStatusText(document.documentStatus, l10n);
    final bool hasImage = document.documentURL.isNotEmpty;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: colorScheme.surface.withValues(alpha: 0),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            if (!hasImage) return;
            _showFullScreenImage(context, title);
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Image Thumbnail ──
              Expanded(
                flex: 3,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Image or placeholder
                    hasImage
                        ? CachedNetworkImage(
                            imageUrl: document.documentURL,
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
                              _getDocumentIcon(document.documentKey),
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
                          vertical: 4,
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
                            Icon(
                              statusIcon,
                              size: 10,
                              color: colorScheme.surface,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              statusText,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: colorScheme.surface,
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
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: colorScheme.shadow.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.zoom_in_rounded,
                            size: 16,
                            color: colorScheme.surface,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // ── Bottom Info ──
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Spacer(),
                      if (document.rejectionReason != null &&
                          document.documentStatus ==
                              DocumentStatus.rejected) ...[
                        Text(
                          document.rejectionReason!,
                          style: TextStyle(
                            fontSize: 10,
                            color: colorScheme.error,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ] else if (document.uploadedAt != null) ...[
                        Row(
                          children: [
                            Icon(
                              Icons.access_time,
                              size: 11,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                DateFormat(
                                  'yyyy/MM/dd',
                                ).format(document.uploadedAt!),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFullScreenImage(BuildContext context, String title) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Theme.of(
          context,
        ).colorScheme.inverseSurface.withValues(alpha: 0.87),
        pageBuilder: (context, animation, secondaryAnimation) {
          return _FullScreenImageViewer(
            imageUrl: document.documentURL,
            title: title,
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  String _getDocumentTitle(DocumentKey key, AppLocalizations l10n) {
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

  IconData _getDocumentIcon(DocumentKey key) {
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

  Color _getStatusColor(DocumentStatus status, ColorScheme colorScheme) {
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

  IconData _getStatusIcon(DocumentStatus status) {
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

  String _getStatusText(DocumentStatus status, AppLocalizations l10n) {
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
