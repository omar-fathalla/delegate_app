import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;

import '../../../admin/domain/entities/company.dart';
import '../../../marketing/presentation/pages/marketing_delegates_screen.dart';

/// بطاقة عرض نتيجة الشركة
/// Company result card widget
class CompanyResultCard extends StatelessWidget {
  final Company company;

  const CompanyResultCard({super.key, required this.company});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant, width: 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => MarketingDelegatesScreen(
                organizationUID: company.organizationUID,
                companyUID: company.uid,
                companyName: company.name,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // الصف الأول: الأيقونة والاسم
              Row(
                children: [
                  // أيقونة الشركة
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.business_rounded,
                      color: colorScheme.onPrimaryContainer,
                      size: 24,
                    ),
                  ),

                  const SizedBox(width: 12),

                  // اسم الشركة
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
                        if (company.companyCodeInOrg.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            'الكود: ${company.companyCodeInOrg}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ] else if (company.code != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            'الكود: ${company.code}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // سهم للتفاصيل
                  Icon(Icons.chevron_right_rounded, color: colorScheme.outline),
                ],
              ),

              const SizedBox(height: 12),

              // الفاصل
              Divider(color: colorScheme.outlineVariant, height: 1),

              const SizedBox(height: 12),

              // معلومات إضافية
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  // النوع
                  _buildInfoChip(
                    context,
                    icon: Icons.category_rounded,
                    label: company.type,
                    color: colorScheme.tertiaryContainer,
                    textColor: colorScheme.onTertiaryContainer,
                  ),

                  // الحالة
                  _buildInfoChip(
                    context,
                    icon: Icons.check_circle_rounded,
                    label: _getStatusLabel(company.status, isArabic),
                    color: _getStatusColor(company.status, colorScheme),
                    textColor: _getStatusTextColor(company.status, colorScheme),
                  ),

                  // عدد المندوبين
                  if (company.delegates > 0)
                    _buildInfoChip(
                      context,
                      icon: Icons.people_rounded,
                      label: '${company.delegates} مندوب',
                      color: colorScheme.secondaryContainer,
                      textColor: colorScheme.onSecondaryContainer,
                    ),

                  // الدفع المؤجل
                  if (company.deferredPayment)
                    _buildInfoChip(
                      context,
                      icon: Icons.payment_rounded,
                      label: 'دفع مؤجل',
                      color: colorScheme.primaryContainer,
                      textColor: colorScheme.onPrimaryContainer,
                    ),
                ],
              ),

              // معلومات الاتصال (إذا وُجدت)
              if (company.phone != null || company.email != null) ...[
                const SizedBox(height: 12),
                Divider(color: colorScheme.outlineVariant, height: 1),
                const SizedBox(height: 12),
                if (company.phone != null)
                  _buildContactInfo(
                    context,
                    icon: Icons.phone_rounded,
                    text: company.phone!,
                  ),
                if (company.email != null) ...[
                  if (company.phone != null) const SizedBox(height: 6),
                  _buildContactInfo(
                    context,
                    icon: Icons.email_rounded,
                    text: company.email!,
                  ),
                ],
              ],

              // تاريخ الإنشاء
              const SizedBox(height: 12),
              Text(
                'تاريخ الإنشاء: ${_formatDate(company.createdAt, isArabic)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// بناء Chip للمعلومات
  Widget _buildInfoChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required Color textColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: textColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

  /// بناء معلومات الاتصال
  Widget _buildContactInfo(
    BuildContext context, {
    required IconData icon,
    required String text,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      children: [
        Icon(icon, size: 16, color: colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  /// الحصول على تسمية الحالة
  String _getStatusLabel(String status, bool isArabic) {
    if (!isArabic) return status;

    switch (status.toLowerCase()) {
      case 'active':
        return 'نشط';
      case 'inactive':
        return 'غير نشط';
      case 'pending':
        return 'معلق';
      case 'suspended':
        return 'موقوف';
      default:
        return status;
    }
  }

  /// الحصول على لون الحالة
  Color _getStatusColor(String status, ColorScheme colorScheme) {
    switch (status.toLowerCase()) {
      case 'active':
        return colorScheme.primaryContainer;
      case 'inactive':
        return colorScheme.surfaceContainerHighest;
      case 'pending':
        return colorScheme.tertiaryContainer;
      case 'suspended':
        return colorScheme.errorContainer;
      default:
        return colorScheme.surfaceContainerHighest;
    }
  }

  /// الحصول على لون نص الحالة
  Color _getStatusTextColor(String status, ColorScheme colorScheme) {
    switch (status.toLowerCase()) {
      case 'active':
        return colorScheme.onPrimaryContainer;
      case 'inactive':
        return colorScheme.onSurface;
      case 'pending':
        return colorScheme.onTertiaryContainer;
      case 'suspended':
        return colorScheme.onErrorContainer;
      default:
        return colorScheme.onSurface;
    }
  }

  /// تنسيق التاريخ
  String _formatDate(DateTime date, bool isArabic) {
    final formatter = intl.DateFormat('dd MMM yyyy', isArabic ? 'ar' : 'en');
    return formatter.format(date);
  }
}
