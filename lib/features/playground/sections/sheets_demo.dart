import 'package:material_ui/material_ui.dart';

import '../../../core/design/tokens.dart';
import '../../../core/design/widgets/sheets.dart';

/// Bottom sheet examples: short and long modal action sheets, a standard
/// cart sheet over the products, and the adaptive bottom/side sheet.
class SheetsDemo extends StatefulWidget {
  const SheetsDemo({super.key});

  @override
  State<SheetsDemo> createState() => _SheetsDemoState();
}

class _SheetsDemoState extends State<SheetsDemo> {
  String _result = '';

  static const _stores = [
    ('المخزن الرئيسي', 'شارع التحرير، 1,240 صنف'),
    ('فرع المعادي', 'شارع 9، 860 صنف'),
    ('فرع مدينة نصر', 'عباس العقاد، 910 صنف'),
    ('فرع الدقي', 'شارع التحرير، 540 صنف'),
    ('فرع الهرم', 'شارع الهرم، 610 صنف'),
    ('فرع شبرا', 'شارع شبرا، 480 صنف'),
    ('فرع حلوان', 'شارع منصور، 300 صنف'),
    ('فرع 6 أكتوبر', 'المحور المركزي، 720 صنف'),
    ('فرع الشيخ زايد', 'الحي الأول، 390 صنف'),
  ];

  static const _cart = [
    ('سكر أبيض 1 كجم', 2, '65.00'),
    ('زيت عباد الشمس', 1, '89.00'),
    ('شاي ليبتون 100 فتلة', 1, '120.00'),
  ];

  Future<void> _short() async {
    final r = await showActionSheet<String>(
      context: context,
      title: 'سكر أبيض 1 كجم',
      groups: const [
        [
          SheetAction(
            label: 'خصم على الصنف',
            value: 'خصم',
            icon: Icons.percent,
          ),
          SheetAction(label: 'ملاحظة', value: 'ملاحظة', icon: Icons.edit_note),
          SheetAction(
            label: 'تغيير الكمية',
            value: 'الكمية',
            icon: Icons.exposure_outlined,
          ),
        ],
        [
          SheetAction(
            label: 'حذف من السلة',
            value: 'حذف',
            icon: Icons.delete_outline,
          ),
        ],
      ],
    );
    setState(() => _result = r ?? 'اتقفلت من غير اختيار');
  }

  Future<void> _long() async {
    final r = await showActionSheet<String>(
      context: context,
      title: 'نقل الكمية إلى',
      groups: [
        [
          for (final (name, info) in _stores)
            SheetAction(
              label: name,
              value: name,
              icon: Icons.warehouse_outlined,
              supportingText: info,
            ),
        ],
      ],
    );
    setState(() => _result = r ?? 'اتقفلت من غير اختيار');
  }

  Future<void> _adaptive() => showAdaptiveSheet<void>(
    context: context,
    title: 'تفاصيل الصنف',
    builder: (c) => const Column(
      children: [
        ListTile(title: Text('سعر البيع'), trailing: Text('32.50')),
        ListTile(title: Text('سعر الشراء'), trailing: Text('28.00')),
        ListTile(title: Text('المخزون'), trailing: Text('18')),
        ListTile(title: Text('الباركود'), trailing: Text('6221234567890')),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: TashilSpacing.sm,
          runSpacing: TashilSpacing.sm,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.more_horiz),
              label: const Text('خيارات صنف في السلة'),
              onPressed: _short,
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.swap_horiz),
              label: const Text('نقل لفرع (قائمة طويلة)'),
              onPressed: _long,
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.info_outline),
              label: const Text('تفاصيل الصنف (متكيف)'),
              onPressed: _adaptive,
            ),
          ],
        ),
        if (_result.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: TashilSpacing.sm),
            child: Text('النتيجة: $_result', style: text.bodySmall),
          ),
        Padding(
          padding: const EdgeInsets.only(
            top: TashilSpacing.lg,
            bottom: TashilSpacing.sm,
          ),
          child: Text(
            'ورقة عادية (standard): السلة فوق الأصناف، والاتنين شغالين. '
            'اسحبها أو دوس على المقبض.',
            style: text.titleSmall,
          ),
        ),
        Container(
          height: 440,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(TashilRadius.medium),
          ),
          child: Stack(
            children: [
              GridView.count(
                crossAxisCount: 3,
                padding: const EdgeInsets.all(TashilSpacing.sm),
                mainAxisSpacing: TashilSpacing.sm,
                crossAxisSpacing: TashilSpacing.sm,
                children: [
                  for (var i = 0; i < 18; i++)
                    Card.filled(
                      margin: EdgeInsets.zero,
                      child: InkWell(
                        onTap: () {},
                        child: Center(
                          child: Text('صنف ${i + 1}', style: text.labelLarge),
                        ),
                      ),
                    ),
                ],
              ),
              StandardBottomSheet(
                presets: const [0.24, 0.5, 1],
                title: 'السلة (4) · 274.00 ج',
                children: [
                  for (final (name, qty, total) in _cart)
                    ListTile(
                      title: Text(name),
                      subtitle: Text('الكمية $qty'),
                      trailing: Text(total),
                    ),
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.all(TashilSpacing.lg),
                    child: FilledButton(
                      onPressed: () {},
                      child: const Text('إتمام البيع'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
