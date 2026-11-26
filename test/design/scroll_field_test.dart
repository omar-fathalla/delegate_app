import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:delegate_app/core/design/app_theme.dart';
import 'package:delegate_app/core/design/widgets/scroll_field.dart';

final _nums = List.generate(20, (i) => i);

Future<List<T>> _pump<T>(
  WidgetTester t, {
  required List<T> values,
  required T initial,
  bool textInput = false,
  T? Function(String)? parse,
  ScrollFieldSize size = ScrollFieldSize.small,
}) async {
  final changes = <T>[];
  var value = initial;
  await t.pumpWidget(
    MaterialApp(
      theme: TashilTheme.light(),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Center(
            child: StatefulBuilder(
              builder: (c, set) => ScrollField<T>(
                label: 'الكمية',
                values: values,
                value: value,
                size: size,
                format: (v) => '$v',
                parse: parse,
                textInput: textInput,
                onChanged: (v) => set(() {
                  value = v;
                  changes.add(v);
                }),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return changes;
}

void main() {
  testWidgets('swipe moves to the next value and snaps', (t) async {
    final changes = await _pump(t, values: _nums, initial: 5);
    await t.drag(find.byType(ListWheelScrollView), const Offset(0, -70));
    await t.pumpAndSettle();
    expect(changes.last, 6);
    final wheel = t.widget<ListWheelScrollView>(
      find.byType(ListWheelScrollView),
    );
    expect(wheel.physics, isA<FixedExtentScrollPhysics>());
  });

  testWidgets('tapping the value below goes to it', (t) async {
    final changes = await _pump(t, values: _nums, initial: 5);
    await t.tap(find.text('6'));
    await t.pumpAndSettle();
    expect(changes.last, 6);
  });

  testWidgets('arrow keys and screen reader actions move the value', (t) async {
    final changes = await _pump(t, values: _nums, initial: 5);
    await t.tap(find.text('5'));
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pumpAndSettle();
    expect(changes.last, 6);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await t.pumpAndSettle();
    expect(changes.last, 5);
    final s = t.getSemantics(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.increasedValue != null,
      ),
    );
    expect(s.label, 'الكمية');
    expect(s.value, '5');
  });

  testWidgets('keyboard input: valid, Arabic digits, error below', (t) async {
    final changes = await _pump(
      t,
      values: _nums,
      initial: 5,
      textInput: true,
      parse: parseTypedInt,
    );
    expect(find.byType(ListWheelScrollView), findsNothing);
    await t.enterText(find.byType(TextField), '12');
    expect(changes.last, 12);
    await t.enterText(find.byType(TextField), '١٣');
    expect(changes.last, 13);
    await t.enterText(find.byType(TextField), '99');
    await t.pump();
    expect(find.text('قيمة مش موجودة'), findsOneWidget);
  });

  testWidgets('strings auto-complete from the first letters', (t) async {
    final changes = await _pump(
      t,
      values: const ['قطعة', 'علبة', 'كرتونة', 'كيس'],
      initial: 'قطعة',
      textInput: true,
    );
    await t.enterText(find.byType(TextField), 'كر');
    expect(changes.last, 'كرتونة');
    final c = t.widget<TextField>(find.byType(TextField)).controller!;
    expect(c.text, 'كرتونة');
    expect(c.selection.start, 2);
  });

  testWidgets('sizes keep their M3 minimum widths', (t) async {
    for (final (size, w) in [
      (ScrollFieldSize.small, 100.0),
      (ScrollFieldSize.medium, 144.0),
      (ScrollFieldSize.large, 186.0),
    ]) {
      await _pump(t, values: _nums, initial: 1, size: size);
      await t.pumpAndSettle();
      expect(t.getSize(find.byType(AnimatedContainer)).width, w);
    }
  });
}
