import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/company.dart';

/// صفحة تفاصيل الشركة
/// Company details screen
class CompanyDetailsScreen extends StatelessWidget {
  final Company company;

  const CompanyDetailsScreen({super.key, required this.company});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(isArabic ? 'تفاصيل الشركة' : 'Company Details'),
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Company Header Card
            _buildHeaderCard(context, colorScheme, theme, isArabic),

            const SizedBox(height: 16),

            // Basic Information Card
            _buildBasicInfoCard(context, colorScheme, theme, isArabic),

            const SizedBox(height: 16),

            // Statistics Card
            _buildStatisticsCard(context, colorScheme, theme, isArabic),

            if (company.description != null &&
                company.description!.isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildDescriptionCard(context, colorScheme, theme, isArabic),
            ],

            const SizedBox(height: 16),

            // Action Buttons
            _buildActionButtons(context, colorScheme, theme, isArabic),
          ],
        ),
      ),
    );
  }

  // ─── Header Card ────────────────────────────────────────────────
  Widget _buildHeaderCard(
    BuildContext context,
    ColorScheme colorScheme,
    ThemeData theme,
    bool isArabic,
  ) {
    return Card(
      elevation: 0,
      color: colorScheme.primaryContainer.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Company Icon
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.business_rounded,
                size: 48,
                color: colorScheme.onPrimaryContainer,
              ),
            ),

            const SizedBox(height: 16),

            // Company Name
            Text(
              company.name,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 8),

            // Status Badge
            _buildStatusBadge(colorScheme, theme, isArabic),

            const SizedBox(height: 12),

            // Company Codes
            if (company.code != null || company.companyCodeInOrg.isNotEmpty)
              _buildCodeChips(colorScheme, theme, isArabic),
          ],
        ),
      ),
    );
  }

  // ─── Status Badge ───────────────────────────────────────────────
  Widget _buildStatusBadge(
    ColorScheme colorScheme,
    ThemeData theme,
    bool isArabic,
  ) {
    final (color, label, icon) = switch (company.status.toLowerCase()) {
      'active' => (
        colorScheme.primary,
        isArabic ? 'نشط' : 'Active',
        Icons.check_circle_rounded,
      ),
      'inactive' => (
        colorScheme.error,
        isArabic ? 'غير نشط' : 'Inactive',
        Icons.cancel_rounded,
      ),
      'pending' => (
        colorScheme.tertiary,
        isArabic ? 'معلق' : 'Pending',
        Icons.pending_rounded,
      ),
      _ => (colorScheme.outline, company.status, Icons.info_rounded),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Code Chips ─────────────────────────────────────────────────
  Widget _buildCodeChips(
    ColorScheme colorScheme,
    ThemeData theme,
    bool isArabic,
  ) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        if (company.code != null)
          Chip(
            avatar: Icon(
              Icons.tag_rounded,
              size: 16,
              color: colorScheme.primary,
            ),
            label: Text(
              '${isArabic ? 'كود' : 'Code'}: ${company.code}',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            backgroundColor: colorScheme.primaryContainer.withValues(
              alpha: 0.5,
            ),
          ),
        if (company.companyCodeInOrg.isNotEmpty)
          Chip(
            avatar: Icon(
              Icons.numbers_rounded,
              size: 16,
              color: colorScheme.secondary,
            ),
            label: Text(
              '${isArabic ? 'الكود النصي' : 'Text Code'}: ${company.companyCodeInOrg}',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            backgroundColor: colorScheme.secondaryContainer.withValues(
              alpha: 0.5,
            ),
          ),
      ],
    );
  }

  // ─── Basic Info Card ────────────────────────────────────────────
  Widget _buildBasicInfoCard(
    BuildContext context,
    ColorScheme colorScheme,
    ThemeData theme,
    bool isArabic,
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
                    Icons.info_outline_rounded,
                    color: colorScheme.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  isArabic ? 'المعلومات الأساسية' : 'Basic Information',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Company Type
            _buildInfoRow(
              icon: Icons.business_center_rounded,
              label: isArabic ? 'نوع الشركة' : 'Company Type',
              value: _getCompanyTypeLabel(company.type, isArabic),
              colorScheme: colorScheme,
              theme: theme,
            ),

            // Created Date
            _buildInfoRow(
              icon: Icons.calendar_today_rounded,
              label: isArabic ? 'تاريخ الإنشاء' : 'Created Date',
              value: DateFormat(
                'dd MMMM yyyy',
                isArabic ? 'ar' : 'en',
              ).format(company.createdAt),
              colorScheme: colorScheme,
              theme: theme,
            ),

            // Organization UID
            _buildInfoRow(
              icon: Icons.corporate_fare_rounded,
              label: isArabic ? 'معرف المنظمة' : 'Organization ID',
              value: company.organizationUID,
              colorScheme: colorScheme,
              theme: theme,
              showDivider: false,
            ),
          ],
        ),
      ),
    );
  }

  // ─── Statistics Card ────────────────────────────────────────────
  Widget _buildStatisticsCard(
    BuildContext context,
    ColorScheme colorScheme,
    ThemeData theme,
    bool isArabic,
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
                    Icons.bar_chart_rounded,
                    color: colorScheme.secondary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  isArabic ? 'الإحصائيات' : 'Statistics',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Statistics Grid
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    icon: Icons.admin_panel_settings_rounded,
                    label: isArabic ? 'المسؤولين' : 'Admins',
                    value: company.admins.toString(),
                    color: colorScheme.primary,
                    colorScheme: colorScheme,
                    theme: theme,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    icon: Icons.people_rounded,
                    label: isArabic ? 'المندوبين' : 'Delegates',
                    value: company.delegates.toString(),
                    color: colorScheme.secondary,
                    colorScheme: colorScheme,
                    theme: theme,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── Description Card ───────────────────────────────────────────
  Widget _buildDescriptionCard(
    BuildContext context,
    ColorScheme colorScheme,
    ThemeData theme,
    bool isArabic,
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
                    color: colorScheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.description_outlined,
                    color: colorScheme.tertiary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  isArabic ? 'الوصف' : 'Description',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Description Text
            Text(
              company.description!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Action Buttons ─────────────────────────────────────────────
  Widget _buildActionButtons(
    BuildContext context,
    ColorScheme colorScheme,
    ThemeData theme,
    bool isArabic,
  ) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () {
              // Navigate to edit company screen
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    isArabic
                        ? 'تم فتح شاشة تعديل الشركة'
                        : 'Opening Edit Company Screen',
                  ),
                ),
              );
              // TODO: Implement edit company navigation when screen is ready
              // Navigator.push(
              //   context,
              //   MaterialPageRoute(
              //     builder: (_) => EditCompanyScreen(company: company),
              //   ),
              // );
            },
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.edit_rounded),
            label: Text(isArabic ? 'تعديل' : 'Edit'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            onPressed: () {
              // Navigate to company delegates screen
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    isArabic
                        ? 'تم فتح شاشة المندوبين'
                        : 'Opening Delegates Screen',
                  ),
                ),
              );
              // TODO: Implement delegates navigation when screen is ready
              // Navigator.push(
              //   context,
              //   MaterialPageRoute(
              //     builder: (_) => CompanyDelegatesScreen(
              //       organizationUID: company.organizationUID,
              //       companyUID: company.uid,
              //     ),
              //   ),
              // );
            },
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.primary,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.people_rounded),
            label: Text(isArabic ? 'المندوبين' : 'Delegates'),
          ),
        ),
      ],
    );
  }

  // ─── Info Row Widget ────────────────────────────────────────────
  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    required ColorScheme colorScheme,
    required ThemeData theme,
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
            ],
          ),
        ),
        if (showDivider) Divider(height: 1, color: colorScheme.outlineVariant),
      ],
    );
  }

  // ─── Stat Card Widget ───────────────────────────────────────────
  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required ColorScheme colorScheme,
    required ThemeData theme,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 32, color: color),
          const SizedBox(height: 12),
          Text(
            value,
            style: theme.textTheme.headlineMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Get Company Type Label ─────────────────────────────────────
  String _getCompanyTypeLabel(String type, bool isArabic) {
    return switch (type.toLowerCase()) {
      'corporation' => isArabic ? 'شركة مساهمة' : 'Corporation',
      'llc' => isArabic ? 'شركة ذات مسؤولية محدودة' : 'LLC',
      'partnership' => isArabic ? 'شراكة' : 'Partnership',
      'sole_proprietorship' => isArabic ? 'مؤسسة فردية' : 'Sole Proprietorship',
      _ => type,
    };
  }
}
