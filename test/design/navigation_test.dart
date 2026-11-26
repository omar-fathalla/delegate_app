import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:delegate_app/core/design/app_theme.dart';
import 'package:delegate_app/core/design/widgets/navigation.dart';

const _primary = [
  TashilDestination(
    icon: Icons.point_of_sale,
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
    icon: Icons.bar_chart,
    selectedIcon: Icons.bar_chart,
    label: 'التقارير',
  ),
];
const _secondary = [
  TashilDestination(
    icon: Icons.people_outline,
    selectedIcon: Icons.people,
    label: 'العملاء',
  ),
];

Future<List<int>> _pump(
  WidgetTester t,
  double width, {
  bool a11y = false,
}) async {
  t.view.physicalSize = Size(width, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final taps = <int>[];
  await t.pumpWidget(
    MaterialApp(
      theme: TashilTheme.light(),
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(accessibleNavigation: a11y),
        child: child!,
      ),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (c, set) => AdaptiveNavigationScaffold(
            title: 'تسهيل',
            primary: _primary,
            secondary: _secondary,
            selectedIndex: taps.isEmpty ? 0 : taps.last,
            onDestinationSelected: (i) => set(() => taps.add(i)),
            body: ListView.builder(
              itemCount: 60,
              itemBuilder: (_, i) => ListTile(title: Text('سطر $i')),
            ),
          ),
        ),
      ),
    ),
  );
  return taps;
}

double _barVisibleHeight(WidgetTester t) =>
    t.getSize(find.byType(HidingNavigationBar)).height;

void main() {
  testWidgets('compact: 64dp bar with labels and badge, no rail', (t) async {
    await _pump(t, 360);
    expect(find.byType(NavigationRail), findsNothing);
    expect(_barVisibleHeight(t), 64);
    expect(find.text('التقارير'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('bar hides on scroll down and returns on scroll up', (t) async {
    await _pump(t, 360);
    await t.drag(find.byType(ListView), const Offset(0, -300));
    await t.pumpAndSettle();
    expect(_barVisibleHeight(t), 0);
    await t.drag(find.byType(ListView), const Offset(0, 100));
    await t.pumpAndSettle();
    expect(_barVisibleHeight(t), 64);
  });

  testWidgets('bar stays while a screen reader is on', (t) async {
    await _pump(t, 360, a11y: true);
    await t.drag(find.byType(ListView), const Offset(0, -300));
    await t.pumpAndSettle();
    expect(_barVisibleHeight(t), 64);
  });

  testWidgets('compact: secondary destinations in the modal rail', (t) async {
    final taps = await _pump(t, 360);
    expect(find.text('العملاء'), findsNothing);
    await t.tap(find.byTooltip('Open navigation menu'));
    await t.pumpAndSettle();
    expect(find.byType(Drawer), findsOneWidget);
    await t.tap(find.text('العملاء'));
    await t.pumpAndSettle();
    expect(taps, [3]);
    expect(find.byType(Drawer), findsNothing);
  });

  testWidgets('medium: collapsed rail, menu button expands it', (t) async {
    await _pump(t, 900);
    expect(find.byType(NavigationBar), findsNothing);
    NavigationRail rail() => t.widget(find.byType(NavigationRail));
    expect(rail().extended, isFalse);
    expect(rail().minWidth, 96);
    expect(rail().destinations, hasLength(3));
    await t.tap(find.byIcon(Icons.menu));
    await t.pumpAndSettle();
    expect(rail().extended, isTrue);
    expect(rail().destinations, hasLength(4));
    expect(find.text('العملاء'), findsOneWidget);
  });

  testWidgets('large: rail starts expanded', (t) async {
    await _pump(t, 1300);
    expect(
      t.widget<NavigationRail>(find.byType(NavigationRail)).extended,
      isTrue,
    );
  });
}
