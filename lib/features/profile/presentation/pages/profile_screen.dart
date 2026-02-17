import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

class ProfileScreen extends StatelessWidget {
  final Delegate delegate;

  const ProfileScreen({super.key, required this.delegate});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: _ProfileBody(delegate: delegate),
    );
  }
}

class _ProfileBody extends StatelessWidget {
  final Delegate delegate;

  const _ProfileBody({required this.delegate});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    const primaryColor = Color(0xFF0D47A1);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverToBoxAdapter(
              child: _buildProfileHeader(context, primaryColor, l10n),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _TabBarDelegate(
                TabBar(
                  labelColor: primaryColor,
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: primaryColor,
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
    Color primaryColor,
    AppLocalizations l10n,
  ) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [primaryColor, primaryColor.withValues(alpha: 0.85)],
        ),
      ),
      padding: const EdgeInsetsDirectional.fromSTEB(20, 30, 20, 24),
      child: Column(
        children: [
          // Avatar
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.5),
                width: 3,
              ),
            ),
            child: CircleAvatar(
              radius: 45,
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              child: const Icon(Icons.person, size: 50, color: Colors.white),
            ),
          ),
          const SizedBox(height: 14),
          // Name
          Text(
            delegate.fullName,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          // Public ID
          Text(
            '${l10n.delegateId}: ${delegate.delegatePublicId}',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.8),
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 10),
          // Position badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              delegate.position.name.toUpperCase(),
              style: const TextStyle(
                fontSize: 13,
                color: Colors.white,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
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
    if (delegate.documents.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.description_outlined, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              l10n.noDocumentsUploaded,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[500],
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
        childAspectRatio: 0.85,
      ),
      itemCount: delegate.documents.length,
      itemBuilder: (context, index) {
        return _DocumentCard(document: delegate.documents[index], l10n: l10n);
      },
    );
  }

  // ─── Tab 3: Request History ─────────────────────────────────────
  Widget _buildRequestHistoryTab(BuildContext context, AppLocalizations l10n) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_outlined, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            l10n.noRequestsYet,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[500],
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
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      color: Colors.white,
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
                    color: const Color(0xFF0D47A1).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: const Color(0xFF0D47A1), size: 22),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A2E),
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
                  color: const Color(0xFFF0F4FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: const Color(0xFF0D47A1), size: 20),
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
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          Divider(height: 1, color: Colors.grey.withValues(alpha: 0.15)),
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
    final String title = _getDocumentTitle(document.documentKey, l10n);
    final IconData icon = _getDocumentIcon(document.documentKey);
    final Color statusColor = _getStatusColor(document.documentStatus);
    final IconData statusIcon = _getStatusIcon(document.documentStatus);
    final String statusText = _getStatusText(document.documentStatus, l10n);
    final dateFormat = DateFormat('yyyy/MM/dd HH:mm');

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: statusColor.withValues(alpha: 0.3), width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            if (document.documentURL.isEmpty) return;
            final uri = Uri.parse(document.documentURL);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri);
            } else {
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(l10n.errorGeneral)));
              }
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(icon, color: statusColor, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A1A2E),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(statusIcon, size: 12, color: statusColor),
                          const SizedBox(width: 4),
                          Text(
                            statusText,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: statusColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (document.rejectionReason != null &&
                    document.documentStatus == DocumentStatus.rejected) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.red.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Text(
                      document.rejectionReason!,
                      style: TextStyle(fontSize: 12, color: Colors.red[800]),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                const Spacer(),
                Divider(height: 1, color: Colors.grey.withValues(alpha: 0.1)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (document.uploadedAt != null)
                      Text(
                        l10n.uploadedOn(
                          dateFormat.format(document.uploadedAt!),
                        ),
                        style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
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
    }
  }

  Color _getStatusColor(DocumentStatus status) {
    switch (status) {
      case DocumentStatus.approved:
        return const Color(0xFF4CAF50);
      case DocumentStatus.rejected:
        return const Color(0xFFF44336);
      case DocumentStatus.pending:
        return const Color(0xFFFF9800);
      case DocumentStatus.not_provided:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(DocumentStatus status) {
    switch (status) {
      case DocumentStatus.approved:
        return Icons.check_circle_outline;
      case DocumentStatus.rejected:
        return Icons.error_outline;
      case DocumentStatus.pending:
        return Icons.access_time;
      case DocumentStatus.not_provided:
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
      case DocumentStatus.not_provided:
        return l10n.notProvidedStatus;
    }
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
    return Container(color: Colors.white, child: tabBar);
  }

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  bool shouldRebuild(covariant _TabBarDelegate oldDelegate) => false;
}
