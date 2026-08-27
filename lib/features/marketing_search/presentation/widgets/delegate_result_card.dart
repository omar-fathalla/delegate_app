import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' as intl;

import '../../../profile/domain/entities/delegate.dart';

/// بطاقة عرض نتيجة المندوب
/// Delegate result card widget
class DelegateResultCard extends StatelessWidget {
  final Delegate delegate;

  const DelegateResultCard({super.key, required this.delegate});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant, width: 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          context.push('/profile', extra: delegate);
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // الصف الأول: الأيقونة والاسم
              Row(
                children: [
                  // أيقونة المندوب
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.person_rounded,
                      color: colorScheme.onSecondaryContainer,
                      size: 24,
                    ),
                  ),

                  const SizedBox(width: 12),

                  // اسم المندوب
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          delegate.fullName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          delegate.phoneNumber,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.secondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
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
                  // الرقم القومي
                  _buildInfoChip(
                    context,
                    icon: Icons.badge_rounded,
                    label: delegate.nationalityID,
                    color: colorScheme.tertiaryContainer,
                    textColor: colorScheme.onTertiaryContainer,
                  ),

                  // الجنس
                  _buildInfoChip(
                    context,
                    icon: delegate.gender == DelegateGender.male
                        ? Icons.male_rounded
                        : Icons.female_rounded,
                    label: _getGenderLabel(delegate.gender, isArabic),
                    color: colorScheme.primaryContainer,
                    textColor: colorScheme.onPrimaryContainer,
                  ),

                  // المنصب
                  _buildInfoChip(
                    context,
                    icon: Icons.work_rounded,
                    label: _getPositionLabel(delegate.position, isArabic),
                    color: colorScheme.secondaryContainer,
                    textColor: colorScheme.onSecondaryContainer,
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // معلومات إضافية
              _buildInfoRow(
                context,
                icon: Icons.cake_rounded,
                label: 'تاريخ الميلاد',
                value: _formatDate(delegate.birthDate, isArabic),
              ),

              const SizedBox(height: 6),

              _buildInfoRow(
                context,
                icon: Icons.location_city_rounded,
                label: 'المدينة',
                value: delegate.city,
              ),

              const SizedBox(height: 6),

              _buildInfoRow(
                context,
                icon: Icons.business_rounded,
                label: 'الشركة',
                value: delegate.companyName,
              ),

              // تاريخ الإنشاء
              const SizedBox(height: 12),
              Divider(color: colorScheme.outlineVariant, height: 1),
              const SizedBox(height: 12),
              Text(
                'تاريخ التسجيل: ${_formatDate(delegate.createdAt, isArabic)}',
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

  /// بناء صف معلومات
  Widget _buildInfoRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      children: [
        Icon(icon, size: 16, color: colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.outline,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  /// الحصول على تسمية الجنس
  String _getGenderLabel(DelegateGender gender, bool isArabic) {
    if (!isArabic) {
      return gender == DelegateGender.male ? 'Male' : 'Female';
    }
    return gender == DelegateGender.male ? 'ذكر' : 'أنثى';
  }

  /// الحصول على تسمية المنصب
  String _getPositionLabel(DelegatePosition position, bool isArabic) {
    if (!isArabic) {
      return position == DelegatePosition.supervisor
          ? 'Supervisor'
          : 'Promoter';
    }
    return position == DelegatePosition.supervisor ? 'مشرف' : 'مندوب';
  }

  /// تنسيق التاريخ
  String _formatDate(DateTime date, bool isArabic) {
    final formatter = intl.DateFormat('dd MMM yyyy', isArabic ? 'ar' : 'en');
    return formatter.format(date);
  }
}
