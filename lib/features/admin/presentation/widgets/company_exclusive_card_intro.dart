import 'package:flutter/material.dart';

/// Badge row, title, and body of the company multi-org card on admin home.
class CompanyExclusiveCardIntro extends StatelessWidget {
  const CompanyExclusiveCardIntro({
    super.key,
    required this.isArabic,
    required this.isFreePromotion,
  });

  final bool isArabic;
  final bool isFreePromotion;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // الشارة الترويجية (Badge) - ميزة حصرية للشركات + عرض مجاني حتى 31/12
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.business_rounded,
                    size: 14,
                    color: colorScheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isArabic ? 'ميزة حصرية للشركات' : 'Exclusive for Companies',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
            if (isFreePromotion) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF86EFAC)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.local_offer_rounded,
                      size: 14,
                      color: Color(0xFF16A34A),
                    ),
                    SizedBox(width: 5),
                    Text(
                      'مجاناً حتى 31/12',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF15803D),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),

        // عنوان الكارت بأيقونة جوجل ماتيريال (بدون إيموجي)
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.hub_rounded,
                color: colorScheme.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                isArabic
                    ? 'متابعة مناديبك في كافة السلاسل من مكان واحد'
                    : 'Track Your Delegates Across All Retail Chains',
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                  letterSpacing: 0.1,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // نص الوصف
        Text(
          isArabic
              ? (isFreePromotion
                  ? 'يمكنك الآن إضافة المناديب للسلاسل والمنظمات الأخرى ومتابعة حضورهم وانصرافهم ورفع التصوير مجاناً بالكامل حتى 31/12 بدون أي رسوم اشتراك.'
                  : 'الآن يمكن لشركتك إضافة ومتابعة حضور وانصراف مناديبها المتواجدين في فروع السلاسل التجارية والمنظمات الأخرى، مع تقارير انضباط ميداني موحدة ولحظية.')
              : 'Your company can now add and track delegate attendance across partner retail chains and organizations in real time from this dashboard.',
          style: TextStyle(
            fontSize: 13,
            height: 1.5,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 14),

      ],
    );
  }
}
