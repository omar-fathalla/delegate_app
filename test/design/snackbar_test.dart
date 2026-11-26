import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:delegate_app/core/design/app_theme.dart';
import 'package:delegate_app/core/design/widgets/snackbars.dart';

Future<void> _app(
  WidgetTester t,
  void Function(BuildContext) onTap, {
  double width = 360,
  bool fab = false,
}) async {
  t.view.physicalSize = Size(width, 700);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: TashilTheme.light(),
      builder: (c, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: Scaffold(
        floatingActionButton: fab
            ? FloatingActionButton(
                onPressed: () {},
                child: const Icon(Icons.add),
              )
            : null,
        body: Builder(
          builder: (c) => Center(
            child: TextButton(
              onPressed: () => onTap(c),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('no action: hides by itself after 4 seconds, no close', (
    t,
  ) async {
    await _app(t, (c) => showTashilSnackBar(c, 'اتبعت للطابعة'));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    expect(find.text('اتبعت للطابعة'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNothing);
    final bar = t.widget<SnackBar>(find.byType(SnackBar));
    expect(bar.behavior, isNull, reason: 'floating comes from the theme');
    await t.pump(const Duration(seconds: 5));
    await t.pumpAndSettle();
    expect(find.text('اتبعت للطابعة'), findsNothing);
  });

  testWidgets('with an action: stays, has a close button, action runs', (
    t,
  ) async {
    var undone = 0;
    await _app(
      t,
      (c) => showTashilSnackBar(
        c,
        'اتشال صنف',
        actionLabel: 'تراجع',
        onAction: () => undone++,
      ),
    );
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    await t.pump(const Duration(seconds: 10));
    await t.pumpAndSettle();
    expect(find.text('اتشال صنف'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
    await t.tap(find.text('تراجع'));
    await t.pumpAndSettle();
    expect(undone, 1);
    expect(find.text('اتشال صنف'), findsNothing);
  });

  testWidgets('close button dismisses a persistent snackbar', (t) async {
    await _app(
      t,
      (c) => showTashilSnackBar(
        c,
        'اتشال صنف',
        actionLabel: 'تراجع',
        onAction: () {},
      ),
    );
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    await t.tap(find.byIcon(Icons.close));
    await t.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a new snackbar replaces the current one straight away', (
    t,
  ) async {
    var n = 0;
    await _app(t, (c) => showTashilSnackBar(c, 'رسالة ${++n}'));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    expect(find.text('رسالة 1'), findsNothing);
    expect(find.text('رسالة 2'), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('compact: full width with margins; from 600dp centred', (
    t,
  ) async {
    await _app(t, (c) => showTashilSnackBar(c, 'اتحفظ'));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    expect(t.widget<SnackBar>(find.byType(SnackBar)).width, isNull);

    await _app(t, (c) => showTashilSnackBar(c, 'اتحفظ'), width: 1200);
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    final r = t.getRect(find.byType(Material).last);
    expect(r.width, lessThanOrEqualTo(560));
    expect(r.center.dx, closeTo(600, 1));
  });

  testWidgets('floats above the FAB', (t) async {
    await _app(t, (c) => showTashilSnackBar(c, 'اتحفظ'), fab: true);
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    final fab = t.getRect(find.byType(FloatingActionButton));
    final bar = t.getRect(
      find
          .ancestor(of: find.text('اتحفظ'), matching: find.byType(Material))
          .first,
    );
    expect(bar.bottom, lessThanOrEqualTo(fab.top));
  });

  testWidgets('text is capped at two lines', (t) async {
    await _app(t, (c) => showTashilSnackBar(c, 'كلام طويل ' * 40));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    final text = t.widget<Text>(find.textContaining('كلام طويل'));
    expect(text.maxLines, 2);
  });
}
