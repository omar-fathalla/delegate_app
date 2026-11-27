import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

import 'package:delegate_app/core/design/tokens.dart';
import 'package:delegate_app/core/design/widgets/summary_card.dart';

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

    // Read-only values: icon + text, never chips (TAS-384).
    Widget value(IconData icon, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: TashilSpacing.xs),
        Text(
          text,
          style: theme.textTheme.labelMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );

    // TAS-392: one SummaryCard per result, like the delegate pages.
    return SummaryCard(
      icon: Icons.person_rounded,
      title: delegate.fullName,
      subtitle: delegate.phoneNumber,
      labels: [
        value(
          Icons.work_rounded,
          _getPositionLabel(delegate.position, isArabic),
        ),
        value(
          delegate.gender == DelegateGender.male
              ? Icons.male_rounded
              : Icons.female_rounded,
          _getGenderLabel(delegate.gender, isArabic),
        ),
        if (delegate.city.isNotEmpty)
          value(Icons.location_city_rounded, delegate.city),
      ],
      facts: [
        SummaryFact(
          label: isArabic ? 'الرقم القومي' : 'National ID',
          value: delegate.nationalityID,
          icon: Icons.badge_rounded,
        ),
        SummaryFact(
          label: isArabic ? 'الشركة' : 'Company',
          value: delegate.companyName.isEmpty ? '—' : delegate.companyName,
          icon: Icons.business_rounded,
        ),
      ],
      margin: EdgeInsets.zero,
      onTap: () => context.push('/profile', extra: delegate),
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
}
