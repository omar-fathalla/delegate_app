import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:delegate_app/core/design/app_theme.dart';
import 'package:delegate_app/core/design/widgets/side_sheets.dart';

Future<void> _app(
  WidgetTester t,
  Widget Function(BuildContext) b, {
  double width = 800,
}) async {
  t.view.physicalSize = Size(width, 700);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: TashilTheme.light(),
      builder: (c, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: Scaffold(body: Builder(builder: b)),
    ),
  );
}

Widget _opener(
  BuildContext c,
  void Function(String?) done, {
  bool detached = true,
  bool back = false,
}) => Center(
  child: TextButton(
    onPressed: () async => done(
      await showSideSheet<String>(
        context: c,
        title: 'الفلاتر',
        detached: detached,
        showBack: back,
        builder: (_) => const Text('محتوى'),
        actions: (s) => [
          FilledButton(
            onPressed: () => Navigator.pop(s, 'applied'),
            child: const Text('تطبيق'),
          ),
        ],
      ),
    ),
    child: const Text('open'),
  ),
);

Rect _sheet(WidgetTester t) => t.getRect(
  find
      .ancestor(
        of: find.byType(SideSheetPanel),
        matching: find.byType(Material),
      )
      .first,
);

void main() {
  testWidgets('modal: at the end edge (left in RTL), detached, max 400', (
    t,
  ) async {
    String? r = 'none';
    await _app(t, (c) => _opener(c, (v) => r = v));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    final rect = _sheet(t);
    expect(rect.left, 16);
    expect(rect.width, 400);
    expect(rect.top, 16);
    expect(find.byType(Divider), findsOneWidget);
    await t.tap(find.text('تطبيق'));
    await t.pumpAndSettle();
    expect(r, 'applied');
  });

  testWidgets('modal on the edge; narrow screens keep some scrim', (t) async {
    await _app(t, (c) => _opener(c, (_) {}, detached: false), width: 360);
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    final rect = _sheet(t);
    expect(rect.left, 0);
    expect(rect.width, 360 - 56);
  });

  testWidgets('close, back and scrim all dismiss', (t) async {
    String? r = 'none';
    await _app(t, (c) => _opener(c, (v) => r = v, back: true));
    for (final close in [
      () => t.tap(find.byIcon(Icons.close)),
      () => t.tap(find.byType(BackButtonIcon)),
      () => t.tapAt(const Offset(780, 350)),
    ]) {
      r = 'none';
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      await close();
      await t.pumpAndSettle();
      expect(find.byType(SideSheetPanel), findsNothing);
      expect(r, isNull);
    }
  });

  testWidgets('drag: a short drag springs back, a long one closes', (t) async {
    await _app(t, (c) => _opener(c, (_) {}));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    final before = _sheet(t);

    final g = await t.startGesture(before.center);
    await g.moveBy(const Offset(-20, 0));
    await g.moveBy(const Offset(-40, 0));
    await t.pump();
    expect(_sheet(t).height, lessThan(before.height), reason: 'detaches');
    await g.up();
    await t.pumpAndSettle();
    expect(_sheet(t).left, closeTo(before.left, 0.5));
    expect(_sheet(t).height, closeTo(before.height, 0.5));

    await t.timedDrag(
      find.byType(SideSheetPanel),
      const Offset(-250, 0),
      const Duration(milliseconds: 800),
    );
    await t.pumpAndSettle();
    expect(find.byType(SideSheetPanel), findsNothing);
  });

  testWidgets('standard: the body shrinks to make room, closes', (t) async {
    var open = false;
    await _app(
      t,
      (c) => StatefulBuilder(
        builder: (c, set) => Column(
          children: [
            TextButton(
              onPressed: () => set(() => open = true),
              child: const Text('open'),
            ),
            Expanded(
              child: StandardSideSheetLayout(
                open: open,
                title: 'تفاصيل',
                onClose: () => set(() => open = false),
                sheet: const Text('محتوى'),
                body: const ColoredBox(key: Key('body'), color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
    expect(t.getSize(find.byKey(const Key('body'))).width, 800);
    expect(find.bySemanticsLabel('تفاصيل'), findsNothing);

    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(t.getSize(find.byKey(const Key('body'))).width, 800 - 320);
    expect(t.getRect(find.byType(SideSheetPanel)).left, closeTo(0, 1));

    await t.tap(find.byIcon(Icons.close));
    await t.pumpAndSettle();
    expect(t.getSize(find.byKey(const Key('body'))).width, 800);
  });
}
