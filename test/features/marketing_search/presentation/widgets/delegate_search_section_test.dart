import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:delegate_app/features/marketing_search/presentation/widgets/delegate_search_section.dart';

void main() {
  testWidgets('DelegateSearchSection renders correctly and triggers onSearch', (tester) async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    bool searchTriggered = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DelegateSearchSection(
            nameController: nameController,
            phoneController: phoneController,
            onSearch: () {
              searchTriggered = true;
            },
          ),
        ),
      ),
    );

    // Verify UI elements
    expect(find.text('اسم المندوب'), findsOneWidget);
    expect(find.text('رقم الموبايل'), findsOneWidget);
    expect(find.text('بحث عن المندوب'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.byType(FilledButton), findsOneWidget);

    // Enter name
    await tester.enterText(find.byType(TextField).first, 'أحمد محمد');
    expect(nameController.text, 'أحمد محمد');

    // Enter phone
    await tester.enterText(find.byType(TextField).last, '01012345678');
    expect(phoneController.text, '01012345678');

    // Tap search button
    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    // Verify callback
    expect(searchTriggered, isTrue);
  });
}
