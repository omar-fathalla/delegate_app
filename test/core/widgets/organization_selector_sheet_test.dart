import 'package:delegate_app/core/widgets/organization_selector_sheet.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

// TAS-296: a smotchi delegate is linked to 39 chains. The login sheet used a
// plain Column, so only the first ~8 cards were reachable on a phone.
void main() {
  final names = List.generate(
    39,
    (i) => 'سلسلة ${i.toString().padLeft(2, '0')}',
  );

  String? lastPicked;

  Future<void> pumpSheet(WidgetTester tester) async {
    lastPicked = null;
    tester.view.physicalSize = const Size(1080, 2400); // M31-like phone
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  isDismissible: false,
                  enableDrag: false,
                  backgroundColor: Colors.transparent,
                  builder: (sheetContext) => OrganizationSelectorSheet(
                    header: const [Text('اختر المنظمة')],
                    itemCount: names.length,
                    itemBuilder: (_, i) => SizedBox(
                      height: 120, // same size as the real org card
                      child: GestureDetector(
                        onTap: () {
                          lastPicked = names[i];
                          Navigator.of(sheetContext).pop();
                        },
                        child: Text(names[i]),
                      ),
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('last of 39 organizations can be scrolled to and picked', (
    tester,
  ) async {
    await pumpSheet(tester);
    expect(tester.takeException(), isNull, reason: 'no overflow');
    expect(find.text('سلسلة 38'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('سلسلة 38'),
      300,
      scrollable: find.descendant(
        of: find.byKey(OrganizationSelectorSheet.listKey),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.text('سلسلة 38'));
    await tester.pumpAndSettle();
    expect(lastPicked, 'سلسلة 38');
    expect(find.text('اختر المنظمة'), findsNothing, reason: 'sheet closed');
  });

  testWidgets('header stays visible while the list scrolls', (tester) async {
    await pumpSheet(tester);
    await tester.drag(
      find.byKey(OrganizationSelectorSheet.listKey),
      const Offset(0, -2000),
    );
    await tester.pumpAndSettle();
    expect(find.text('اختر المنظمة'), findsOneWidget);
  });

  testWidgets('short list sizes to its content (no empty tall sheet)', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: OrganizationSelectorSheet(
              header: const [Text('h')],
              itemCount: 2,
              itemBuilder: (_, i) => SizedBox(height: 50, child: Text('$i')),
            ),
          ),
        ),
      ),
    );
    final h = tester.getSize(find.byType(OrganizationSelectorSheet)).height;
    expect(h, lessThan(250));
  });

  test('sortedByOrganizationName sorts a copy by name', () {
    final input = ['كارفور', 'وكالة المنصورة', ' جملة ماركت'];
    final out = sortedByOrganizationName(input, (s) => s);
    expect(out, [' جملة ماركت', 'كارفور', 'وكالة المنصورة']);
    expect(input.first, 'كارفور', reason: 'caller list unchanged');
  });
}
