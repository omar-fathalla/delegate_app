import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/company.dart';

/// List item widget for displaying company information
class CompanyListItem extends StatelessWidget {
  final Company company;
  final VoidCallback? onTap;

  const CompanyListItem({super.key, required this.company, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outline.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with company name and status
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          company.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        // Display both code fields if available
                        if (company.code != null) ...[
                          Text(
                            '${isArabic ? 'كود الشركة' : 'Company Code'}: ${company.code}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (company.companyCodeInOrg.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              '${isArabic ? 'الكود النصي' : 'Text Code'}: ${company.companyCodeInOrg}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ] else if (company.companyCodeInOrg.isNotEmpty) ...[
                          Text(
                            '${isArabic ? 'كود الشركة' : 'Company Code'}: ${company.companyCodeInOrg}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  _buildStatusChip(context),
                ],
              ),

              const SizedBox(height: 12),

              // Company details
              Row(
                children: [
                  Expanded(
                    child: _buildInfoItem(
                      context,
                      icon: Icons.business_rounded,
                      label: isArabic ? 'النوع' : 'Type',
                      value: _getCompanyTypeLabel(company.type, isArabic),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildInfoItem(
                      context,
                      icon: Icons.calendar_today_rounded,
                      label: isArabic ? 'تاريخ الإنشاء' : 'Created',
                      value: DateFormat(
                        'dd MMM yyyy',
                        isArabic ? 'ar' : 'en',
                      ).format(company.createdAt),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Statistics
              Row(
                children: [
                  Expanded(
                    child: _buildStatItem(
                      context,
                      icon: Icons.admin_panel_settings_rounded,
                      label: isArabic ? 'المسؤولين' : 'Admins',
                      value: company.admins.toString(),
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildStatItem(
                      context,
                      icon: Icons.people_rounded,
                      label: isArabic ? 'المندوبين' : 'Delegates',
                      value: company.delegates.toString(),
                      color: colorScheme.secondary,
                    ),
                  ),
                ],
              ),

              // Optional description
              if (company.description != null &&
                  company.description!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.3,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.description_rounded,
                        size: 16,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          company.description!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Build status chip
  Widget _buildStatusChip(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';

    final (color, label) = switch (company.status.toLowerCase()) {
      'active' => (colorScheme.primary, isArabic ? 'نشط' : 'Active'),
      'inactive' => (colorScheme.error, isArabic ? 'غير نشط' : 'Inactive'),
      'pending' => (colorScheme.tertiary, isArabic ? 'معلق' : 'Pending'),
      _ => (colorScheme.outline, company.status),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// Build info item
  Widget _buildInfoItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      children: [
        Icon(icon, size: 16, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                value,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Build stat item
  Widget _buildStatItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(color: color),
                ),
                Text(
                  value,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Get company type label
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
