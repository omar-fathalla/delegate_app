import 'package:material_ui/material_ui.dart';

import '../../../core/design/tokens.dart';
import '../../../core/design/widgets/search.dart';

/// Search examples: the product search bar, search as an icon button, and
/// a bar that scrolls away with the list.
class SearchDemo extends StatefulWidget {
  const SearchDemo({super.key});

  @override
  State<SearchDemo> createState() => _SearchDemoState();
}

class _SearchDemoState extends State<SearchDemo> {
  String _last = '';

  static const _products = [
    ('سكر أبيض 1 كجم', '6221234567890', '32.50 ج', 18),
    ('زيت عباد الشمس 1 لتر', '6221111111111', '89.00 ج', 4),
    ('أرز مصري 5 كجم', '6222222222222', '145.00 ج', 0),
    ('شاي ليبتون 100 فتلة', '6223333333333', '120.00 ج', 25),
    ('مكرونة 400 جم', '6224444444444', '14.00 ج', 60),
    ('سكر بني 500 جم', '6225555555555', '28.00 ج', 9),
  ];
  static const _suppliers = [
    'شركة السكر المصرية',
    'الشمس للزيوت',
    'النيل للتوزيع',
  ];
  static const _customers = ['أحمد سمير', 'سارة محمود', 'محل الأمل'];

  static List<SearchResultGroup> search(String q, String? filter) {
    bool has(String s) => s.contains(q);
    return [
      if (filter == null || filter == 'أصناف')
        SearchResultGroup('الأصناف', [
          for (final (name, code, price, stock) in _products)
            if (has(name) || code.startsWith(q))
              SearchResult(
                title: name,
                subtitle: '$price · المخزون $stock',
                leading: const CircleAvatar(
                  child: Icon(Icons.inventory_2_outlined),
                ),
                trailing: stock == 0 ? const Text('نفد') : null,
                value: code,
              ),
        ]),
      if (filter == null || filter == 'موردين')
        SearchResultGroup('الموردين', [
          for (final s in _suppliers)
            if (has(s))
              SearchResult(
                title: s,
                leading: const CircleAvatar(
                  child: Icon(Icons.local_shipping_outlined),
                ),
              ),
        ]),
      if (filter == null || filter == 'عملاء')
        SearchResultGroup('العملاء', [
          for (final c in _customers)
            if (has(c))
              SearchResult(
                title: c,
                leading: CircleAvatar(child: Text(c.characters.first)),
              ),
        ]),
    ];
  }

  Widget _frame(Widget child, double height) => Container(
    height: height,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      borderRadius: BorderRadius.circular(TashilRadius.medium),
    ),
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget caption(String s) => Padding(
      padding: const EdgeInsets.only(
        top: TashilSpacing.lg,
        bottom: TashilSpacing.sm,
      ),
      child: Text(s, style: text.titleSmall),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TashilSearch(
          hintText: 'ابحث في الأصناف والموردين',
          recent: const ['سكر', 'زيت'],
          filters: const ['أصناف', 'موردين', 'عملاء'],
          search: search,
          trailing: [
            IconButton(
              tooltip: 'مسح باركود',
              icon: const Icon(Icons.qr_code_scanner),
              onPressed: () {},
            ),
          ],
          onSelected: (r) => setState(() => _last = r.title),
          onSubmitted: (q) => setState(() => _last = 'بحث: $q'),
        ),
        if (_last.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: TashilSpacing.sm),
            child: Text('آخر اختيار: $_last', style: text.bodySmall),
          ),
        caption('البحث كإجراء ثانوي: زرار في شريط التطبيق'),
        _frame(
          Scaffold(
            appBar: AppBar(
              title: const Text('العملاء'),
              actions: [
                TashilSearch(
                  asIconButton: true,
                  tooltip: 'بحث في العملاء',
                  hintText: 'ابحث في العملاء',
                  search: (q, _) => search(q, 'عملاء'),
                ),
              ],
            ),
            body: ListView(
              children: [for (final c in _customers) ListTile(title: Text(c))],
            ),
          ),
          200,
        ),
        caption('شريط بيختفي مع السكرول ويرجع لما تطلع'),
        _frame(
          CustomScrollView(
            slivers: [
              SliverAppBar(
                floating: true,
                snap: true,
                automaticallyImplyLeading: false,
                toolbarHeight: 72,
                titleSpacing: TashilSpacing.page,
                title: TashilSearch(
                  hintText: 'ابحث في الأصناف',
                  search: (q, _) => search(q, 'أصناف'),
                ),
              ),
              SliverList.builder(
                itemCount: 20,
                itemBuilder: (_, i) => ListTile(
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: Text(_products[i % _products.length].$1),
                ),
              ),
            ],
          ),
          320,
        ),
      ],
    );
  }
}
