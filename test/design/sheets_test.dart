import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:delegate_app/core/design/app_theme.dart';
import 'package:delegate_app/core/design/widgets/sheets.dart';

Future<void> _app(
  WidgetTester t,
  Widget Function(BuildContext) b, {
  double width = 360,
}) async {
  t.view.physicalSize = Size(width, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: TashilTheme.light(),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: Builder(builder: b)),
      ),
    ),
  );
}

double _sheetHeight(WidgetTester t) =>
    t.getSize(find.byType(SheetFrame)).height;

void main() {
  testWidgets('short action sheet: content height, returns the choice', (
    t,
  ) async {
    String? result = 'none';
    await _app(
      t,
      (c) => TextButton(
        onPressed: () async => result = await showActionSheet<String>(
          context: c,
          title: 'الصنف',
          groups: const [
            [SheetAction(label: 'خصم', value: 'discount')],
            [SheetAction(label: 'حذف', value: 'delete')],
          ],
        ),
        child: const Text('open'),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(_sheetHeight(t), lessThan(400));
    expect(find.byType(Divider), findsOneWidget);
    expect(find.bySemanticsLabel('تغيير ارتفاع الورقة'), findsNothing);
    await t.tap(find.text('حذف'));
    await t.pumpAndSettle();
    expect(result, 'delete');
  });

  testWidgets('long sheet: half screen, handle tap to full, close button', (
    t,
  ) async {
    int? result = -1;
    await _app(
      t,
      (c) => TextButton(
        onPressed: () async => result = await showActionSheet<int>(
          context: c,
          groups: [
            [
              for (var i = 0; i < 20; i++)
                SheetAction(label: 'فرع $i', value: i, supportingText: 'x'),
            ],
          ],
        ),
        child: const Text('open'),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(_sheetHeight(t), closeTo(400, 1));
    expect(find.byIcon(Icons.close), findsNothing);

    await t.tap(find.bySemanticsLabel('تغيير ارتفاع الورقة'));
    await t.pumpAndSettle();
    expect(_sheetHeight(t), closeTo(800, 1));
    expect(find.byIcon(Icons.close), findsOneWidget);

    await t.tap(find.byIcon(Icons.close));
    await t.pumpAndSettle();
    expect(find.byType(SheetFrame), findsNothing);
    expect(result, isNull);
  });

  testWidgets('scrim closes a modal sheet', (t) async {
    await _app(
      t,
      (c) => TextButton(
        onPressed: () => showActionSheet<int>(
          context: c,
          groups: const [
            [SheetAction(label: 'واحد', value: 1)],
          ],
        ),
        child: const Text('open'),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.tapAt(const Offset(180, 40));
    await t.pumpAndSettle();
    expect(find.byType(SheetFrame), findsNothing);
  });

  testWidgets('standard sheet: handle cycles presets, collapse at full', (
    t,
  ) async {
    var taps = 0;
    await _app(
      t,
      (c) => Stack(
        children: [
          Align(
            alignment: Alignment.topCenter,
            child: TextButton(
              onPressed: () => taps++,
              child: const Text('content'),
            ),
          ),
          StandardBottomSheet(
            presets: const [0.2, 0.5, 1],
            title: 'السلة',
            children: [for (var i = 0; i < 5; i++) Text('سطر $i')],
          ),
        ],
      ),
    );
    expect(_sheetHeight(t), closeTo(160, 1));
    await t.tap(find.text('content'));
    expect(taps, 1, reason: 'content behind a standard sheet stays usable');

    final handle = find.bySemanticsLabel('تغيير ارتفاع الورقة');
    await t.tap(handle);
    await t.pumpAndSettle();
    expect(_sheetHeight(t), closeTo(400, 1));
    await t.tap(handle);
    await t.pumpAndSettle();
    expect(_sheetHeight(t), closeTo(800, 1));
    expect(find.byIcon(Icons.expand_more), findsOneWidget);

    await t.tap(find.byIcon(Icons.expand_more));
    await t.pumpAndSettle();
    expect(_sheetHeight(t), closeTo(160, 1));
  });

  testWidgets('adaptive sheet: bottom on compact, side from 840dp', (t) async {
    Widget opener(BuildContext c) => TextButton(
      onPressed: () => showAdaptiveSheet<void>(
        context: c,
        title: 'تفاصيل',
        builder: (_) => const Text('محتوى'),
      ),
      child: const Text('open'),
    );
    await _app(t, opener);
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    await t.tapAt(const Offset(180, 40));
    await t.pumpAndSettle();

    await _app(t, opener, width: 1000);
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('محتوى'), findsOneWidget);
    expect(t.getSize(find.byType(SideSheetPanel)).width, 400);
    await t.tap(find.byIcon(Icons.close));
    await t.pumpAndSettle();
    expect(find.text('محتوى'), findsNothing);
  });
}
