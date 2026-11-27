import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:delegate_app/features/marketing_search/presentation/widgets/company_search_section.dart';

void main() {
  testWidgets('CompanySearchSection renders correctly and triggers onSearch', (tester) async {
    final controller = TextEditingController();
    bool searchTriggered = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompanySearchSection(
            controller: controller,
            onSearch: () {
              searchTriggered = true;
            },
          ),
        ),
      ),
    );

    // Verify UI elements
    expect(find.text('كود الشركة'), findsOneWidget);
    expect(find.text('بحث عن الشركة'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(FilledButton), findsOneWidget);

    // Enter text
    await tester.enterText(find.byType(TextField), 'COMP123');
    expect(controller.text, 'COMP123');

    // Tap search button
    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    // Verify callback
    expect(searchTriggered, isTrue);
  });
}
