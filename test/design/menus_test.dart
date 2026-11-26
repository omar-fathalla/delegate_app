import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:delegate_app/core/design/app_theme.dart';
import 'package:delegate_app/core/design/widgets/menus.dart';

Widget _app(Widget Function(BuildContext) b) => MaterialApp(
  theme: TashilTheme.light(),
  home: Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      body: Center(child: Builder(builder: b)),
    ),
  ),
);

void main() {
  testWidgets('menu button stays pressed while open; groups; disabled', (
    t,
  ) async {
    var chosen = '';
    await t.pumpWidget(
      _app(
        (c) => MenuButton(
          icon: Icons.more_vert,
          tooltip: 'خيارات',
          style: groupedMenuStyle,
          menuChildren: groupedMenuChildren(c, [
            [MenuOption(label: 'تعديل', onPressed: () => chosen = 'edit')],
            [const MenuOption(label: 'مرتجع', onPressed: null)],
          ]),
        ),
      ),
    );
    IconButton btn() => t.widget<IconButton>(find.byType(IconButton));
    expect(btn().isSelected, isFalse);

    await t.tap(find.byIcon(Icons.more_vert));
    await t.pumpAndSettle();
    expect(btn().isSelected, isTrue);

    // Two groups = two surfaces with a gap between them.
    final groups = find.ancestor(
      of: find.byType(MenuOption),
      matching: find.byWidgetPredicate(
        (w) => w is Material && w.elevation == 3,
      ),
    );
    expect(groups, findsNWidgets(2));
    final gap = t.getTopLeft(groups.last).dy - t.getBottomLeft(groups.first).dy;
    expect(gap, greaterThan(0));

    // Unavailable item is shown disabled, not removed.
    final returnItem = t.widget<MenuItemButton>(
      find.ancestor(
        of: find.text('مرتجع'),
        matching: find.byType(MenuItemButton),
      ),
    );
    expect(returnItem.onPressed, isNull);

    await t.tap(find.text('تعديل'));
    await t.pumpAndSettle();
    expect(chosen, 'edit');
    expect(btn().isSelected, isFalse);
    expect(find.byIcon(Icons.more_vert), findsOneWidget);
  });

  testWidgets('selected option shows a check', (t) async {
    await t.pumpWidget(
      _app(
        (c) => Column(
          children: groupedMenuChildren(c, [
            [
              MenuOption(label: 'نقدي', selected: true, onPressed: () {}),
              MenuOption(label: 'كارت', onPressed: () {}),
            ],
          ], style: MenuColorStyle.vibrant),
        ),
      ),
    );
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('long press opens a context menu', (t) async {
    await t.pumpWidget(
      _app(
        (c) => ContextMenuRegion(
          menuChildren: [
            MenuItemButton(onPressed: () {}, child: const Text('طباعة باركود')),
          ],
          child: const SizedBox(width: 200, height: 60, child: Text('سكر')),
        ),
      ),
    );
    expect(find.text('طباعة باركود'), findsNothing);
    await t.longPress(find.text('سكر'));
    await t.pumpAndSettle();
    expect(find.text('طباعة باركود'), findsOneWidget);
  });

  testWidgets('multi-select menu stays open', (t) async {
    final cols = <String>{};
    await t.pumpWidget(
      _app(
        (c) => StatefulBuilder(
          builder: (c, set) => MenuAnchor(
            menuChildren: [
              for (final x in ['الكمية', 'الربح'])
                CheckboxMenuButton(
                  value: cols.contains(x),
                  closeOnActivate: false,
                  onChanged: (v) =>
                      set(() => v == true ? cols.add(x) : cols.remove(x)),
                  child: Text(x),
                ),
            ],
            builder: (c, ctl, _) =>
                TextButton(onPressed: ctl.open, child: const Text('أعمدة')),
          ),
        ),
      ),
    );
    await t.tap(find.text('أعمدة'));
    await t.pumpAndSettle();
    await t.tap(find.text('الكمية'));
    await t.pumpAndSettle();
    await t.tap(find.text('الربح'));
    await t.pumpAndSettle();
    expect(cols, {'الكمية', 'الربح'});
    expect(find.byType(CheckboxMenuButton), findsNWidgets(2));
  });
}
