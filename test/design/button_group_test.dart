import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:delegate_app/core/design/app_theme.dart';
import 'package:delegate_app/core/design/widgets/button_group.dart';

Widget _host(Widget child) => MaterialApp(
  theme: TashilTheme.light(),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  const items = [
    ButtonGroupItem(value: 'a', label: 'A'),
    ButtonGroupItem(value: 'b', label: 'B'),
    ButtonGroupItem(value: 'c', label: 'C'),
  ];

  testWidgets('connected single-select keeps one value selected', (
    tester,
  ) async {
    var selected = {'a'};
    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) => ButtonGroup<String>(
            variant: ButtonGroupVariant.connected,
            items: items,
            selected: selected,
            onSelectionChanged: (v) => setState(() => selected = v),
          ),
        ),
      ),
    );
    await tester.tap(find.text('B'));
    await tester.pumpAndSettle();
    expect(selected, {'b'});
    // Selection required: tapping the only selected value keeps it.
    await tester.tap(find.text('B'));
    await tester.pumpAndSettle();
    expect(selected, {'b'});
  });

  testWidgets('multi-select toggles values independently', (tester) async {
    var selected = <String>{};
    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) => ButtonGroup<String>(
            items: items,
            multiSelect: true,
            selectionRequired: false,
            selected: selected,
            onSelectionChanged: (v) => setState(() => selected = v),
          ),
        ),
      ),
    );
    await tester.tap(find.text('A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('C'));
    await tester.pumpAndSettle();
    expect(selected, {'a', 'c'});
    await tester.tap(find.text('A'));
    await tester.pumpAndSettle();
    expect(selected, {'c'});
  });

  testWidgets('action group reports presses', (tester) async {
    String? pressed;
    await tester.pumpWidget(
      _host(ButtonGroup<String>(items: items, onPressed: (v) => pressed = v)),
    );
    await tester.tap(find.text('C'));
    expect(pressed, 'c');
  });
}
