import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:delegate_app/core/design/app_theme.dart';
import 'package:delegate_app/core/design/widgets/tooltips.dart';

Future<void> _app(WidgetTester t, Widget child, {double width = 360}) async {
  t.view.physicalSize = Size(width, 700);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: TashilTheme.light(),
      builder: (c, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: Scaffold(body: child),
    ),
  );
}

Rect _box(WidgetTester t, String text) => t.getRect(
  find.ancestor(of: find.text(text), matching: find.byType(Material)).first,
);

void main() {
  testWidgets('plain: above the icon button, 4dp gap, gone 1.5 s after', (
    t,
  ) async {
    await _app(
      t,
      Center(
        child: IconButton(
          tooltip: 'مزامنة',
          icon: const Icon(Icons.sync),
          onPressed: () {},
        ),
      ),
    );
    await t.longPress(find.byType(IconButton));
    await t.pumpAndSettle();
    final icon = t.getRect(find.byType(IconButton));
    final tip = t.getRect(
      find
          .ancestor(of: find.text('مزامنة'), matching: find.byType(Container))
          .first,
    );
    expect(tip.bottom, closeTo(icon.center.dy - 24, 1));
    expect(tip.bottom, lessThan(icon.top + 4 + 1));
    await t.pump(const Duration(milliseconds: 1000));
    expect(find.text('مزامنة'), findsOneWidget);
    await t.pump(const Duration(milliseconds: 600));
    await t.pumpAndSettle();
    expect(find.text('مزامنة'), findsNothing);
  });

  testWidgets('plain in an app bar: below the icon', (t) async {
    await _app(
      t,
      Padding(
        padding: const EdgeInsets.only(top: 200),
        child: TooltipTheme(
          data: appBarTooltipTheme,
          child: AppBar(
            actions: [
              IconButton(
                tooltip: 'فلترة',
                icon: const Icon(Icons.filter_list),
                onPressed: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await t.longPress(find.byType(IconButton));
    await t.pumpAndSettle();
    final icon = t.getRect(find.byType(IconButton));
    final tip = t.getRect(
      find
          .ancestor(of: find.text('فلترة'), matching: find.byType(Container))
          .first,
    );
    expect(tip.top, greaterThan(icon.center.dy));
  });

  testWidgets('transient rich: below, towards the end side, not covering', (
    t,
  ) async {
    await _app(
      t,
      const Align(
        // Right side: in RTL the tooltip grows to the left from here.
        alignment: Alignment.centerRight,
        child: RichTooltip(
          subhead: 'متوسط التكلفة',
          text: 'متوسط سعر الشرا',
          child: SizedBox(width: 80, height: 40, child: Text('هدف')),
        ),
      ),
    );
    await t.longPress(find.text('هدف'));
    await t.pumpAndSettle();
    final target = t.getRect(find.byType(SizedBox).last);
    final tip = _box(t, 'متوسط سعر الشرا');
    expect(tip.top, closeTo(target.bottom + 4, 1));
    expect(tip.right, closeTo(target.center.dx, 1), reason: 'RTL: grows left');
    expect(tip.overlaps(target), isFalse);
    await t.pump(const Duration(seconds: 2));
    await t.pumpAndSettle();
    expect(find.text('متوسط سعر الشرا'), findsNothing);
  });

  test('position moves back on screen in 8dp steps, flips above', () {
    final p = richTooltipPosition(
      target: const Rect.fromLTWH(300, 650, 40, 40),
      tooltip: const Size(200, 100),
      overlay: const Size(360, 700),
      direction: TextDirection.ltr,
    );
    expect(p.dx + 200, lessThanOrEqualTo(360 - 8));
    expect((p.dx - 320) % 8, 0);
    expect(p.dy, 650 - 4 - 100);
  });

  testWidgets('persistent rich: tap opens, stays, tap elsewhere closes', (
    t,
  ) async {
    await _app(
      t,
      Column(
        children: [
          const SizedBox(height: 100),
          RichTooltip(
            persistent: true,
            subhead: 'الرصيد الآجل',
            text: 'فلوس العملا',
            actions: [
              TextButton(onPressed: () {}, child: const Text('التفاصيل')),
            ],
            child: const Text('الرصيد'),
          ),
          const SizedBox(height: 300),
          const Text('بعيد'),
        ],
      ),
    );
    await t.tap(find.text('الرصيد'));
    await t.pumpAndSettle();
    await t.pump(const Duration(seconds: 5));
    expect(find.text('فلوس العملا'), findsOneWidget);
    await t.tap(find.text('التفاصيل'));
    await t.pump();
    expect(find.text('فلوس العملا'), findsOneWidget);
    await t.tap(find.text('بعيد'));
    await t.pumpAndSettle();
    expect(find.text('فلوس العملا'), findsNothing);
  });

  testWidgets('controller opens a persistent one; only one at a time', (
    t,
  ) async {
    final a = RichTooltipController();
    final b = RichTooltipController();
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    await _app(
      t,
      Column(
        children: [
          RichTooltip(
            persistent: true,
            controller: a,
            text: 'أ',
            child: const Text('1'),
          ),
          const SizedBox(height: 200),
          RichTooltip(
            persistent: true,
            controller: b,
            text: 'ب',
            child: const Text('2'),
          ),
        ],
      ),
    );
    a.show();
    await t.pumpAndSettle();
    expect(find.text('أ'), findsOneWidget);
    b.show();
    await t.pumpAndSettle();
    expect(find.text('أ'), findsNothing);
    expect(find.text('ب'), findsOneWidget);
  });

  testWidgets('at most two buttons', (t) async {
    await _app(
      t,
      const RichTooltip(
        text: 'x',
        actions: [SizedBox(), SizedBox(), SizedBox()],
        child: SizedBox(),
      ),
    );
    expect(t.takeException(), isAssertionError);
  });
}
