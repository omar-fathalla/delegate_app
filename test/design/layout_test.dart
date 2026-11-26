import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:delegate_app/core/design/app_theme.dart';
import 'package:delegate_app/core/design/layout.dart';
import 'package:delegate_app/core/design/tokens.dart';
import 'package:delegate_app/core/design/widgets/navigation.dart';
import 'package:delegate_app/core/design/widgets/toolbar.dart';

class _Pane extends StatelessWidget {
  const _Pane(this.name);
  final String name;
  @override
  Widget build(BuildContext context) =>
      SizedBox.expand(key: ValueKey(name), child: Text(name));
}

const _first = _Pane('القايمة');
const _second = _Pane('التفاصيل');
const _third = _Pane('التصفية');

Future<void> _app(
  WidgetTester t,
  double width,
  Widget child, {
  TextDirection dir = TextDirection.rtl,
}) async {
  t.view.physicalSize = Size(width, 700);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: TashilTheme.light(),
      builder: (c, w) => Directionality(textDirection: dir, child: w!),
      home: Scaffold(body: child),
    ),
  );
}

Rect _rect(WidgetTester t, String name) =>
    t.getRect(find.byKey(ValueKey(name)));

void main() {
  test('five breakpoints with the M3 widths', () {
    final cases = {
      0.0: TashilBreakpoint.compact,
      599.0: TashilBreakpoint.compact,
      600.0: TashilBreakpoint.medium,
      839.0: TashilBreakpoint.medium,
      840.0: TashilBreakpoint.expanded,
      1199.0: TashilBreakpoint.expanded,
      1200.0: TashilBreakpoint.large,
      1599.0: TashilBreakpoint.large,
      1600.0: TashilBreakpoint.extraLarge,
      2400.0: TashilBreakpoint.extraLarge,
    };
    cases.forEach((w, b) => expect(TashilBreakpoint.fromWidth(w), b));
    expect(TashilBreakpoint.medium.minWidth, TashilSizes.compactMax);
    expect(TashilBreakpoint.expanded.minWidth, TashilSizes.mediumMax);
    expect(
      TashilBreakpoint.large.minWidth,
      AdaptiveNavigationScaffold.expandedFrom,
    );
  });

  test('margins, spacer, panes and fixed pane width per breakpoint', () {
    expect(TashilBreakpoint.compact.margin, 16);
    for (final b in TashilBreakpoint.values.skip(1)) {
      expect(b.margin, 24);
      expect(b.spacer, 24);
    }
    expect(
      [for (final b in TashilBreakpoint.values) b.maxPanes],
      [1, 2, 2, 2, 3],
    );
    expect(
      [for (final b in TashilBreakpoint.values) b.recommendedPanes],
      [1, 1, 2, 2, 3],
    );
    expect(TashilBreakpoint.expanded.fixedPaneWidth, 360);
    expect(TashilBreakpoint.large.fixedPaneWidth, 412);
    expect(TashilBreakpoint.medium.fixedPaneWidth, isNull);
  });

  testWidgets('compact: one pane, the open item replaces the list', (t) async {
    await _app(
      t,
      360,
      const PaneLayout(first: _first, second: _second, showSecond: false),
    );
    expect(find.text('القايمة'), findsOneWidget);
    expect(find.text('التفاصيل'), findsNothing);
    expect(_rect(t, 'القايمة').right, closeTo(360 - 16, 0.5));
    expect(_rect(t, 'القايمة').left, closeTo(16, 0.5));

    await _app(
      t,
      360,
      const PaneLayout(first: _first, second: _second, showSecond: true),
    );
    expect(find.text('القايمة'), findsNothing);
    expect(find.text('التفاصيل'), findsOneWidget);
  });

  testWidgets('medium: one pane unless two are asked for, then 50/50', (
    t,
  ) async {
    await _app(t, 700, const PaneLayout(first: _first, second: _second));
    expect(find.text('التفاصيل'), findsNothing);

    await _app(
      t,
      700,
      const PaneLayout(first: _first, second: _second, twoPanesOnMedium: true),
    );
    final a = _rect(t, 'القايمة');
    final b = _rect(t, 'التفاصيل');
    expect(a.width, closeTo((700 - 48 - 24) / 2, 0.5));
    expect(b.width, closeTo(a.width, 0.5));
  });

  testWidgets('expanded: fixed 360dp list on the right in Arabic, 24dp '
      'margins and spacer', (t) async {
    await _app(t, 1000, const PaneLayout(first: _first, second: _second));
    final list = _rect(t, 'القايمة');
    final detail = _rect(t, 'التفاصيل');
    expect(list.width, 360);
    expect(list.right, 1000 - 24);
    expect(list.left - detail.right, 24);
    expect(detail.left, 24);
  });

  testWidgets('placeholder fills the second pane when nothing is open', (
    t,
  ) async {
    await _app(
      t,
      1000,
      const PaneLayout(first: _first, placeholder: Text('اختار فاتورة')),
    );
    expect(find.text('اختار فاتورة'), findsOneWidget);
  });

  testWidgets('extra-large: third pane is 400dp; never shown below it', (
    t,
  ) async {
    const layout = PaneLayout(first: _first, second: _second, third: _third);
    await _app(t, 1700, layout);
    expect(_rect(t, 'التصفية').width, 400);
    expect(_rect(t, 'القايمة').width, 412);

    await _app(t, 1300, layout);
    expect(find.text('التصفية'), findsNothing);
  });

  testWidgets('drag handle resizes, collapses at the edge, and comes back', (
    t,
  ) async {
    await _app(t, 1000, const PaneLayout(first: _first, second: _second));
    final handle = find.byType(PaneDragHandle);
    // RTL: the list is on the right, dragging left makes it wider. The
    // first 20dp of a drag are the touch slop.
    await t.drag(handle, const Offset(-120, 0));
    await t.pumpAndSettle();
    expect(_rect(t, 'القايمة').width, closeTo(460, 1));

    await t.drag(handle, const Offset(800, 0));
    await t.pumpAndSettle();
    expect(find.text('القايمة'), findsNothing);
    expect(find.text('التفاصيل'), findsOneWidget);

    await t.drag(find.byType(PaneDragHandle), const Offset(-60, 0));
    await t.pumpAndSettle();
    expect(find.text('القايمة'), findsOneWidget);
    expect(_rect(t, 'القايمة').width, 360);
  });

  testWidgets('drag handle: resize cursor, keyboard and screen reader', (
    t,
  ) async {
    await _app(t, 1000, const PaneLayout(first: _first, second: _second));
    final semantics = t.getSemantics(find.byType(PaneDragHandle));
    expect(semantics.label, contains('تغيير عرض الأجزاء'));
    final region = t.widget<MouseRegion>(
      find
          .descendant(
            of: find.byType(PaneDragHandle),
            matching: find.byType(MouseRegion),
          )
          .first,
    );
    expect(region.cursor, SystemMouseCursors.resizeColumn);
  });

  testWidgets('FAB swaps to extended FAB from expanded', (t) async {
    Widget fab() =>
        AdaptiveFab(icon: Icons.add, label: 'فاتورة جديدة', onPressed: () {});
    await _app(t, 360, Center(child: Builder(builder: (_) => fab())));
    expect(find.text('فاتورة جديدة'), findsNothing);
    expect(find.byTooltip('فاتورة جديدة'), findsOneWidget);

    await _app(t, 1000, Center(child: Builder(builder: (_) => fab())));
    expect(find.text('فاتورة جديدة'), findsOneWidget);
  });

  testWidgets('reading width keeps lines near 60 characters', (t) async {
    late double max;
    await _app(
      t,
      1600,
      Builder(
        builder: (c) {
          max = ReadingWidth.maxWidthFor(c);
          return ReadingWidth(child: Text('كلام ' * 200));
        },
      ),
    );
    expect(max, closeTo(60 * 16 * 0.55, 1));
    expect(t.getSize(find.byType(Text)).width, lessThanOrEqualTo(max));
  });

  testWidgets('navigation: medium two-pane layout keeps the bar', (t) async {
    Widget nav({required bool bar}) => AdaptiveNavigationScaffold(
      title: 'تسهيل',
      primary: const [
        TashilDestination(
          icon: Icons.point_of_sale,
          selectedIcon: Icons.point_of_sale,
          label: 'البيع',
        ),
        TashilDestination(
          icon: Icons.inventory_2_outlined,
          selectedIcon: Icons.inventory_2,
          label: 'المخزون',
        ),
        TashilDestination(
          icon: Icons.bar_chart,
          selectedIcon: Icons.bar_chart,
          label: 'التقارير',
        ),
      ],
      selectedIndex: 0,
      onDestinationSelected: (_) {},
      barOnMedium: bar,
      body: const SizedBox(),
    );
    await _app(t, 700, nav(bar: false));
    expect(find.byType(NavigationRail), findsOneWidget);
    await _app(t, 700, nav(bar: true));
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    await _app(t, 1000, nav(bar: true));
    expect(find.byType(NavigationRail), findsOneWidget);
  });

  testWidgets('split: spacer centred in the window even with a rail', (
    t,
  ) async {
    await _app(
      t,
      1000,
      const NavigationInset(
        width: 96,
        child: PaneLayout(
          first: _first,
          second: _second,
          split: PaneSplit.split,
        ),
      ),
    );
    // Window = 96 rail + 1000. Half of it minus the rail, margin, half spacer.
    expect(_rect(t, 'القايمة').width, closeTo((1096 / 2) - 96 - 24 - 12, 0.5));
  });

  testWidgets('flexible-fixed: the supporting pane at the end is 360dp', (
    t,
  ) async {
    await _app(
      t,
      1000,
      const PaneLayout(
        first: _first,
        second: _second,
        split: PaneSplit.flexibleFixed,
      ),
    );
    expect(_rect(t, 'التفاصيل').width, 360);
    expect(_rect(t, 'التفاصيل').left, 24);
  });

  testWidgets('released handle snaps to 412dp', (t) async {
    await _app(t, 1000, const PaneLayout(first: _first, second: _second));
    // 20dp slop + 40dp: 400dp, within 32dp of 412.
    await t.drag(find.byType(PaneDragHandle), const Offset(-60, 0));
    await t.pumpAndSettle();
    expect(_rect(t, 'القايمة').width, 412);
  });

  testWidgets('tap on the handle toggles one and two panes', (t) async {
    await _app(t, 1000, const PaneLayout(first: _first, second: _second));
    await t.tap(find.byType(PaneDragHandle));
    await t.pumpAndSettle();
    expect(find.text('القايمة'), findsNothing);
    expect(find.text('التفاصيل'), findsOneWidget);
    await t.tap(find.byType(PaneDragHandle));
    await t.pumpAndSettle();
    expect(find.text('القايمة'), findsOneWidget);
  });

  testWidgets('persistent: width and collapse survive breakpoint changes', (
    t,
  ) async {
    final c = PaneLayoutController();
    Widget layout() =>
        PaneLayout(controller: c, first: _first, second: _second);
    await _app(t, 1000, layout());
    c.resize(412);
    await t.pump();
    await _app(t, 1300, layout());
    expect(_rect(t, 'القايمة').width, 412);

    c.collapseTo(PaneCollapse.secondOnly);
    await _app(t, 700, layout());
    await _app(t, 1000, layout());
    expect(find.text('القايمة'), findsNothing, reason: 'stays collapsed');
    expect(PaneLayoutController(sizedWidth: 360).sizedWidth, 360);
  });

  testWidgets('temporary: back to the default width after the pane closes', (
    t,
  ) async {
    final c = PaneLayoutController();
    Widget layout(bool open) => PaneLayout(
      controller: c,
      resizing: PaneResizing.temporary,
      first: _first,
      second: open ? _second : null,
      placeholder: const _Pane('فاضي'),
    );
    await _app(t, 1000, layout(true));
    c.resize(500);
    await t.pump();
    expect(_rect(t, 'القايمة').width, 500);
    await _app(t, 1000, layout(false));
    await t.pump();
    await _app(t, 1000, layout(true));
    expect(_rect(t, 'القايمة').width, 360);
  });

  testWidgets('reflow: compact stacks the supporting pane under the first', (
    t,
  ) async {
    await _app(
      t,
      360,
      const PaneLayout(first: _first, second: _second, reflow: true),
    );
    final a = _rect(t, 'القايمة');
    final b = _rect(t, 'التفاصيل');
    expect(b.top, greaterThan(a.bottom));
    expect(b.top - a.bottom, 24);
  });

  group('scaffold: bars and rails', () {
    const dests = [
      TashilDestination(
        icon: Icons.point_of_sale,
        selectedIcon: Icons.point_of_sale,
        label: 'البيع',
      ),
      TashilDestination(
        icon: Icons.inventory_2_outlined,
        selectedIcon: Icons.inventory_2,
        label: 'المخزون',
      ),
      TashilDestination(
        icon: Icons.bar_chart,
        selectedIcon: Icons.bar_chart,
        label: 'التقارير',
      ),
    ];
    Widget scaffold() => AdaptiveNavigationScaffold(
      title: 'الفواتير',
      primary: dests,
      selectedIndex: 0,
      onDestinationSelected: (_) {},
      actions: [
        IconButton(
          tooltip: 'بحث',
          onPressed: () {},
          icon: const Icon(Icons.search),
        ),
      ],
      toolbar: [
        ToolbarAction(icon: Icons.print, label: 'طباعة', onPressed: () {}),
        ToolbarAction(icon: Icons.share, label: 'مشاركة', onPressed: () {}),
      ],
      body: Builder(
        builder: (c) => Text('inset ${NavigationInset.of(c).round()}'),
      ),
    );

    testWidgets('compact: horizontal toolbar above the navigation bar', (
      t,
    ) async {
      await _app(t, 360, scaffold());
      final bar = t.getRect(find.byType(NavigationBar));
      final tb = t.getRect(find.byType(TashilToolbar));
      expect(tb.bottom, lessThan(bar.top));
      expect(tb.width, greaterThan(tb.height));
      expect(find.byTooltip('بحث'), findsOneWidget);
    });

    testWidgets('medium and up: vertical toolbar in the trailing rail, '
        'panes know the rail width', (t) async {
      await _app(t, 1000, scaffold());
      final tb = t.getRect(find.byType(TashilToolbar));
      expect(tb.height, greaterThan(tb.width));
      // RTL: trailing side is the left edge.
      expect(tb.left, lessThan(AdaptiveNavigationScaffold.trailingRailWidth));
      expect(find.text('inset 96'), findsOneWidget);
    });

    test('app bar takes at most two actions', () {
      expect(
        () => AdaptiveNavigationScaffold(
          title: 'x',
          primary: dests,
          selectedIndex: 0,
          onDestinationSelected: (_) {},
          actions: const [SizedBox(), SizedBox(), SizedBox()],
          body: const SizedBox(),
        ),
        throwsAssertionError,
      );
    });
  });
}
