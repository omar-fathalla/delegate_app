import 'package:material_ui/material_ui.dart';

import '../../../core/design/tokens.dart';
import '../../../core/design/widgets/tooltips.dart';

/// Tooltip examples from Tashil: plain tooltips on icon-only buttons and
/// on an abbreviation, below the icons in an app bar, a transient rich
/// tooltip that explains "average cost", a persistent one on a stat card,
/// and one that introduces a new feature from code.
class TooltipsDemo extends StatefulWidget {
  const TooltipsDemo({super.key});

  @override
  State<TooltipsDemo> createState() => _TooltipsDemoState();
}

class _TooltipsDemoState extends State<TooltipsDemo> {
  final _feature = RichTooltipController();

  @override
  void dispose() {
    _feature.dispose();
    super.dispose();
  }

  Widget _caption(String s) => Padding(
    padding: const EdgeInsets.only(
      top: TashilSpacing.lg,
      bottom: TashilSpacing.sm,
    ),
    child: Text(s, style: Theme.of(context).textTheme.titleSmall),
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _caption('عادي: أزرار أيقونة بس (اضغط ضغطة طويلة)'),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconButton(
              tooltip: 'مزامنة دلوقتي',
              icon: const Icon(Icons.sync),
              onPressed: () {},
            ),
            IconButton(
              tooltip: 'طباعة آخر فاتورة',
              icon: const Icon(Icons.print_outlined),
              onPressed: () {},
            ),
            IconButton(
              tooltip: 'مسح باركود',
              icon: const Icon(Icons.qr_code_scanner),
              onPressed: () {},
            ),
            const SizedBox(width: TashilSpacing.lg),
            // Bare text has no boundary: 8dp gap instead of 4.
            Tooltip(
              message: 'ضريبة القيمة المضافة',
              verticalOffset: 10 + TashilTooltip.gapFromText,
              child: Text('ض.ق.م 14%', style: text.bodyLarge),
            ),
          ],
        ),
        _caption('في شريط التطبيق: التلميح تحت الأيقونة'),
        ClipRRect(
          borderRadius: BorderRadius.circular(TashilRadius.medium),
          child: TooltipTheme(
            data: appBarTooltipTheme,
            child: AppBar(
              automaticallyImplyLeading: false,
              backgroundColor: scheme.surfaceContainer,
              title: const Text('الأصناف'),
              actions: [
                IconButton(
                  tooltip: 'فلترة',
                  icon: const Icon(Icons.filter_list),
                  onPressed: () {},
                ),
                IconButton(
                  tooltip: 'إضافة صنف',
                  icon: const Icon(Icons.add),
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ),
        _caption('غني مؤقت: شرح مصطلح (ضغطة طويلة أو مرور الماوس)'),
        RichTooltip(
          subhead: 'متوسط التكلفة',
          text:
              'متوسط سعر الشرا لكل الكميات اللي في المخزن دلوقتي. بيتحسب '
              'من جديد مع كل فاتورة شرا.',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text('متوسط التكلفة: 23.40 ج.م', style: text.bodyLarge),
              ),
              const SizedBox(width: TashilSpacing.xs),
              Icon(Icons.info_outline, size: 18, color: scheme.primary),
            ],
          ),
        ),
        _caption('غني ثابت: بيفتح بالضغط ويفضل لحد ما تضغط في حتة تانية'),
        RichTooltip(
          persistent: true,
          subhead: 'الرصيد الآجل',
          text:
              'فلوس العملا اللي اشتروا بالآجل ولسه مدفعوش. اضغط "التفاصيل" '
              'تشوف كل عميل لوحده.',
          actions: [
            TextButton(onPressed: () {}, child: const Text('التفاصيل')),
          ],
          child: Card.outlined(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(TashilSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('الرصيد الآجل', style: text.labelLarge),
                  Text('4,250.00 ج.م', style: text.titleLarge),
                ],
              ),
            ),
          ),
        ),
        _caption('شرح ميزة جديدة (بيفتح لوحده أول ما الصفحة تفتح)'),
        Wrap(
          spacing: TashilSpacing.md,
          runSpacing: TashilSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            RichTooltip(
              persistent: true,
              controller: _feature,
              subhead: 'جديد: تقفيل الوردية',
              text:
                  'بتطبع ملخص الوردية وتقارن الفلوس اللي في الدرج باللي '
                  'المفروض يكون فيه.',
              actions: [
                TextButton(onPressed: () {}, child: const Text('اعرف أكتر')),
                TextButton(onPressed: _feature.hide, child: const Text('تمام')),
              ],
              child: FilledButton.tonal(
                onPressed: () {},
                child: const Text('تقفيل الوردية'),
              ),
            ),
            TextButton(onPressed: _feature.show, child: const Text('جرب فتحه')),
          ],
        ),
      ],
    );
  }
}
