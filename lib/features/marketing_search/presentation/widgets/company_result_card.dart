import 'package:material_ui/material_ui.dart';
import 'package:delegate_app/core/design/tokens.dart';
import 'package:delegate_app/core/design/widgets/summary_card.dart';

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

    final code = company.companyCodeInOrg.isNotEmpty
        ? company.companyCodeInOrg
        : company.code?.toString();

    // TAS-392: one SummaryCard per result; status is the only coloured label.
    return SummaryCard(
      icon: Icons.business_rounded,
      title: company.name,
      subtitle: code == null ? null : 'الكود: $code',
      labels: [
        SummaryLabel(
          _getStatusLabel(company.status, isArabic),
          container: _getStatusColor(company.status, colorScheme),
          onContainer: _getStatusTextColor(company.status, colorScheme),
        ),
        if (company.type.isNotEmpty)
          value(Icons.category_rounded, company.type),
        if (company.delegates > 0)
          value(Icons.people_rounded, '${company.delegates} مندوب'),
        if (company.deferredPayment) value(Icons.payment_rounded, 'دفع مؤجل'),
      ],
      facts: [
        if (company.phone != null)
          SummaryFact(
            label: isArabic ? 'الهاتف' : 'Phone',
            value: company.phone!,
            icon: Icons.phone_rounded,
          ),
        if (company.email != null)
          SummaryFact(
            label: isArabic ? 'البريد' : 'Email',
            value: company.email!,
            icon: Icons.email_rounded,
          ),
      ],
      margin: EdgeInsets.zero,
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
}
