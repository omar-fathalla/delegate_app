import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:delegate_app/core/design/app_theme.dart';
import 'package:delegate_app/core/design/widgets/chips.dart';

Widget _host(Widget child) => MaterialApp(
  theme: TashilTheme.light(),
  home: Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(body: Center(child: child)),
  ),
);

class _Field extends StatefulWidget {
  const _Field();
  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
  List<String> values = ['111'];
  @override
  Widget build(BuildContext context) => InputChipField(
    label: 'باركود',
    values: values,
    onChanged: (v) => setState(() => values = v),
  );
}

void main() {
  testWidgets('input chip field: Enter adds, Backspace selects then deletes', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const _Field()));
    final state = tester.state<_FieldState>(find.byType(_Field));
    await tester.tap(find.byType(TextField));
    await tester.pump();

    // Type "222" after the sentinel and submit.
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '​222',
        selection: TextSelection.collapsed(offset: 4),
      ),
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(state.values, ['111', '222']);

    // Comma also commits.
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '​333،',
        selection: TextSelection.collapsed(offset: 5),
      ),
    );
    await tester.pump();
    expect(state.values, ['111', '222', '333']);

    Future<void> backspace() async {
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '',
          selection: TextSelection.collapsed(offset: 0),
        ),
      );
      await tester.pump();
    }

    await backspace();
    expect(state.values, ['111', '222', '333'], reason: 'first press selects');
    final last = tester.widget<InputChip>(find.byType(InputChip).last);
    expect(last.selected, isTrue);

    await backspace();
    expect(state.values, ['111', '222']);

    // ✕ removes a chip.
    await tester.tap(find.byTooltip('إزالة 111'));
    await tester.pump();
    expect(state.values, ['222']);
  });

  testWidgets('menu filter chip: whole chip opens the menu', (tester) async {
    String? value;
    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) => MenuFilterChip<String>(
            label: 'التصنيف',
            value: value,
            options: const {'d': 'مشروبات', 'g': 'بقالة'},
            onChanged: (v) => setState(() => value = v),
          ),
        ),
      ),
    );
    expect(tester.widget<FilterChip>(find.byType(FilterChip)).selected, false);
    expect(
      tester.getSize(find.byType(FilterChip)).height,
      greaterThanOrEqualTo(48),
    );

    await tester.tap(find.text('التصنيف'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('بقالة'));
    await tester.pumpAndSettle();

    expect(value, 'g');
    expect(find.text('بقالة'), findsOneWidget);
    expect(tester.widget<FilterChip>(find.byType(FilterChip)).selected, true);
  });
}
