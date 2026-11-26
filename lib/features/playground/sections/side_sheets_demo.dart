import 'package:material_ui/material_ui.dart';

import '../../../core/design/tokens.dart';
import '../../../core/design/widgets/side_sheets.dart';

/// Side sheet examples: a modal filters sheet (detached, with bottom
/// actions and drag-to-close), and a standard sheet beside a product
/// table on a wide screen, where the table shrinks to make room.
class SideSheetsDemo extends StatefulWidget {
  const SideSheetsDemo({super.key});

  @override
  State<SideSheetsDemo> createState() => _SideSheetsDemoState();
}

class _SideSheetsDemoState extends State<SideSheetsDemo> {
  static const _categories = ['بقالة', 'منظفات', 'مشروبات', 'ألبان', 'معلبات'];
  Set<String> _applied = {'بقالة'};
  bool _standardOpen = false;
  String _selected = 'سكر أبيض 1 كجم';

  Future<void> _filters({bool detached = true}) async {
    final picked = {..._applied};
    final r = await showSideSheet<Set<String>>(
      context: context,
      title: 'الفلاتر',
      detached: detached,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: TashilSpacing.lg,
                vertical: TashilSpacing.sm,
              ),
              child: Text('القسم', style: Theme.of(c).textTheme.titleSmall),
            ),
            for (final cat in _categories)
              CheckboxListTile(
                value: picked.contains(cat),
                title: Text(cat),
                onChanged: (v) =>
                    set(() => v! ? picked.add(cat) : picked.remove(cat)),
              ),
            const Divider(),
            SwitchListTile(
              value: picked.contains('قليل المخزون'),
              title: const Text('قليل المخزون بس'),
              onChanged: (v) => set(
                () => v
                    ? picked.add('قليل المخزون')
                    : picked.remove('قليل المخزون'),
              ),
            ),
          ],
        ),
      ),
      actions: (c) => [
        FilledButton(
          onPressed: () => Navigator.pop(c, picked),
          child: const Text('تطبيق'),
        ),
        OutlinedButton(
          onPressed: () => Navigator.pop(c),
          child: Text(MaterialLocalizations.of(c).cancelButtonLabel),
        ),
      ],
    );
    if (r != null) setState(() => _applied = r);
  }

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
              icon: const Icon(Icons.filter_list),
              label: const Text('فلاتر (modal منفصلة)'),
              onPressed: _filters,
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.filter_list),
              label: const Text('فلاتر (modal على الحافة)'),
              onPressed: () => _filters(detached: false),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: TashilSpacing.sm),
          child: Text(
            'الفلاتر المطبقة: ${_applied.join('، ')}',
            style: text.bodySmall,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(
            top: TashilSpacing.lg,
            bottom: TashilSpacing.sm,
          ),
          child: Text(
            'Standard على شاشة عريضة (تابلت 840): الجدول بيضيق عشان الورقة '
            'تاخد مكانها، والاتنين شغالين.',
            style: text.titleSmall,
          ),
        ),
        Container(
          height: 300,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(TashilRadius.medium),
          ),
          child: FittedBox(
            child: SizedBox(
              width: 840,
              height: 560,
              child: Scaffold(
                appBar: AppBar(
                  title: const Text('الأصناف'),
                  actions: [
                    IconButton(
                      tooltip: 'تفاصيل الصنف',
                      isSelected: _standardOpen,
                      icon: const Icon(Icons.info_outline),
                      selectedIcon: const Icon(Icons.info),
                      onPressed: () =>
                          setState(() => _standardOpen = !_standardOpen),
                    ),
                    const SizedBox(width: TashilSpacing.sm),
                  ],
                ),
                body: StandardSideSheetLayout(
                  open: _standardOpen,
                  title: 'تفاصيل الصنف',
                  onClose: () => setState(() => _standardOpen = false),
                  actions: [
                    FilledButton.tonal(
                      onPressed: () {},
                      child: const Text('تعديل'),
                    ),
                  ],
                  sheet: Column(
                    children: [
                      ListTile(title: Text(_selected)),
                      const ListTile(
                        title: Text('سعر البيع'),
                        trailing: Text('32.50'),
                      ),
                      const ListTile(
                        title: Text('المخزون'),
                        trailing: Text('18'),
                      ),
                    ],
                  ),
                  body: ListView(
                    children: [
                      for (final p in [
                        'سكر أبيض 1 كجم',
                        'زيت عباد الشمس',
                        'أرز مصري 5 كجم',
                        'شاي ليبتون 100 فتلة',
                        'مكرونة 400 جم',
                        'صابون سائل',
                      ])
                        ListTile(
                          selected: _standardOpen && p == _selected,
                          leading: const Icon(Icons.inventory_2_outlined),
                          title: Text(p),
                          trailing: const Text('32.50'),
                          onTap: () => setState(() {
                            _selected = p;
                            _standardOpen = true;
                          }),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
