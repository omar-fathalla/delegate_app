import 'package:material_ui/material_ui.dart';

import '../../../core/design/tokens.dart';
import '../../../core/design/widgets/button_group.dart';
import '../../../core/design/widgets/navigation.dart';
import 'common.dart';

class NavigationSection extends StatefulWidget {
  const NavigationSection({super.key});

  @override
  State<NavigationSection> createState() => _NavigationSectionState();
}

class _NavigationSectionState extends State<NavigationSection> {
  int _rail = 0;
  int _modal = 0;
  int _adaptive = 0;
  bool _railExpanded = false;
  double _width = 360;

  static const _primary = [
    TashilDestination(
      icon: Icons.point_of_sale_outlined,
      selectedIcon: Icons.point_of_sale,
      label: 'البيع',
    ),
    TashilDestination(
      icon: Icons.inventory_2_outlined,
      selectedIcon: Icons.inventory_2,
      label: 'المخزون',
      badge: 3,
    ),
    TashilDestination(
      icon: Icons.bar_chart_outlined,
      selectedIcon: Icons.bar_chart,
      label: 'التقارير',
    ),
    TashilDestination(
      icon: Icons.sync_outlined,
      selectedIcon: Icons.sync,
      label: 'المزامنة',
      badge: 0,
    ),
  ];

  static const _secondary = [
    TashilDestination(
      icon: Icons.people_outline,
      selectedIcon: Icons.people,
      label: 'العملاء',
    ),
    TashilDestination(
      icon: Icons.local_shipping_outlined,
      selectedIcon: Icons.local_shipping,
      label: 'الموردين',
    ),
    TashilDestination(
      icon: Icons.receipt_long_outlined,
      selectedIcon: Icons.receipt_long,
      label: 'المصروفات',
    ),
    TashilDestination(
      icon: Icons.schedule_outlined,
      selectedIcon: Icons.schedule,
      label: 'الوردية',
    ),
  ];

  static const _all = [..._primary, ..._secondary];

  Widget _frame(Widget child, {double height = 200}) => Container(
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
    return SectionList([
      SpecSection(
        title: 'شريط التنقل السفلي',
        m3: 'Navigation bar',
        spec: 'components/navigation-bar/guidelines',
        rule:
            'التنقل الرئيسي على SUNMI V3 (compact). 3 لـ 5 وجهات، والاسم '
            'ظاهر دايماً تحت الأيقونة، وارتفاعه 64. بيختفي لما تنزل في '
            'المحتوى ويرجع لما تطلع. ما يتحطش مع القضيب الجانبي في نفس الشاشة.',
        children: [_frame(_BarDemo(dest: _primary), height: 320)],
      ),
      SpecSection(
        title: 'القضيب الجانبي',
        m3: 'Navigation rail',
        spec: 'components/navigation-rail/guidelines',
        rule:
            'بدل الشريط السفلي من عرض 600 (تابلت أو شاشة أفقية). مضغوط '
            '(96) والأسماء تحت الأيقونات، وزرار القائمة فوق بيفرده عشان '
            'يبان كل الوجهات. زرار الإضافة (FAB) تحت زرار القائمة.',
        children: [
          _frame(
            Row(
              children: [
                TashilNavigationRail(
                  primary: _primary,
                  secondary: _secondary,
                  selectedIndex: _rail,
                  expanded: _railExpanded,
                  onMenu: () => setState(() => _railExpanded = !_railExpanded),
                  onDestinationSelected: (i) => setState(() => _rail = i),
                  fab: (
                    icon: Icons.add,
                    label: 'فاتورة جديدة',
                    onPressed: () {},
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: Center(child: Text(_all[_rail].label))),
              ],
            ),
            height: 460,
          ),
        ],
      ),
      SpecSection(
        title: 'القضيب الممتد المنبثق (بدل القائمة الجانبية)',
        m3: 'Navigation drawer',
        spec: 'components/navigation-drawer/guidelines',
        rule:
            'M3 ما بقاش بينصح بالـ Navigation drawer. الوجهات الثانوية '
            '(العملاء، الموردين، المصروفات، الوردية) بقت في القضيب الممتد. '
            'على الموبايل بيفتح فوق المحتوى من زرار القائمة في شريط التطبيق.',
        children: [
          _frame(
            Scaffold(
              appBar: AppBar(title: const Text('تسهيل')),
              drawer: ModalNavigationRail(
                primary: _primary,
                secondary: _secondary,
                selectedIndex: _modal,
                onDestinationSelected: (i) => setState(() => _modal = i),
              ),
              body: Center(child: Text(_all[_modal].label)),
            ),
            height: 320,
          ),
        ],
      ),
      SpecSection(
        title: 'تنقل متكيف حسب حجم الشاشة',
        m3: 'Adaptive design',
        spec: 'components/navigation-rail/guidelines#adaptive-design',
        rule:
            'AdaptiveNavigationScaffold بيختار لوحده: أقل من 600 شريط '
            'سفلي، من 600 قضيب مضغوط، من 1200 قضيب ممتد. اختار عرض الشاشة:',
        children: [
          ButtonGroup<double>(
            variant: ButtonGroupVariant.connected,
            selected: {_width},
            onSelectionChanged: (v) => setState(() => _width = v.first),
            items: const [
              ButtonGroupItem(value: 360, label: '360'),
              ButtonGroupItem(value: 840, label: '840'),
              ButtonGroupItem(value: 1280, label: '1280'),
            ],
          ),
          const SizedBox(height: TashilSpacing.md),
          _frame(
            FittedBox(
              child: SizedBox(
                width: _width,
                height: 640,
                child: AdaptiveNavigationScaffold(
                  key: ValueKey(_width),
                  title: 'تسهيل',
                  primary: _primary,
                  secondary: _secondary,
                  selectedIndex: _adaptive,
                  onDestinationSelected: (i) => setState(() => _adaptive = i),
                  fab: (
                    icon: Icons.add,
                    label: 'فاتورة جديدة',
                    onPressed: () {},
                  ),
                  body: ListView.builder(
                    itemCount: 30,
                    itemBuilder: (_, i) => ListTile(
                      title: Text('${_all[_adaptive].label} ${i + 1}'),
                    ),
                  ),
                ),
              ),
            ),
            height: 400,
          ),
        ],
      ),
      SpecSection(
        title: 'التبويبات',
        m3: 'Tabs',
        spec: 'components/tabs',
        children: [
          _frame(
            const DefaultTabController(
              length: 3,
              child: Column(
                children: [
                  TabBar(
                    tabs: [
                      Tab(text: 'الكل'),
                      Tab(text: 'قليل'),
                      Tab(text: 'نفد'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        Center(child: Text('كل الأصناف')),
                        Center(child: Text('قليل المخزون')),
                        Center(child: Text('نفد')),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            height: 160,
          ),
        ],
      ),
      SpecSection(
        title: 'شريط التطبيق',
        m3: 'Top app bar',
        spec: 'components/top-app-bar',
        rule: 'Small app bar في الشاشات العادية. العنوان على البداية (يمين).',
        children: [
          _frame(
            Scaffold(
              appBar: AppBar(
                leading: const BackButton(),
                title: const Text('تفاصيل الصنف'),
                actions: [
                  IconButton(
                    tooltip: 'تعديل',
                    onPressed: () {},
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    tooltip: 'المزيد',
                    onPressed: () {},
                    icon: const Icon(Icons.more_vert),
                  ),
                ],
              ),
            ),
            height: 64,
          ),
        ],
      ),
    ]);
  }
}

/// A screen with a long list and the hiding navigation bar.
class _BarDemo extends StatefulWidget {
  const _BarDemo({required this.dest});
  final List<TashilDestination> dest;

  @override
  State<_BarDemo> createState() => _BarDemoState();
}

class _BarDemoState extends State<_BarDemo> {
  final _visible = HideOnScroll();
  int _i = 0;

  @override
  void dispose() {
    _visible.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: _visible.listener(
      child: ListView.builder(
        itemCount: 30,
        itemBuilder: (_, n) => ListTile(
          title: Text('${widget.dest[_i].label}: سطر ${n + 1}'),
          subtitle: n == 0 ? const Text('انزل في القائمة: الشريط يختفي') : null,
        ),
      ),
    ),
    bottomNavigationBar: HidingNavigationBar(
      visible: _visible,
      destinations: widget.dest,
      selectedIndex: _i,
      onDestinationSelected: (i) => setState(() => _i = i),
    ),
  );
}
