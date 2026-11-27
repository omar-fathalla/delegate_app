import 'package:delegate_app/config/theme/app_theme.dart';
import 'package:delegate_app/core/design/widgets/button_group.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// The item's name is read once: the Text inside used to merge with the
/// Semantics label («مندوب\nمندوب»), so screen readers said it twice and the
/// Maestro login journeys (`visible: "مندوب"`) never matched (Mac gate,
/// 27 Nov 2026, TAS-387).
void main() {
  testWidgets('each item exposes its label once', (t) async {
    final handle = t.ensureSemantics();
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        home: Scaffold(
          body: ButtonGroup<String>(
            variant: ButtonGroupVariant.connected,
            selected: const {'a'},
            onSelectionChanged: (_) {},
            items: const [
              ButtonGroupItem(value: 'a', label: 'مندوب'),
              ButtonGroupItem(value: 'b', label: 'موظف إداري'),
            ],
          ),
        ),
      ),
    );
    expect(find.bySemanticsLabel('مندوب'), findsOneWidget);
    expect(find.bySemanticsLabel('موظف إداري'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('مندوب\\nمندوب')), findsNothing);
    handle.dispose();
  });
}
