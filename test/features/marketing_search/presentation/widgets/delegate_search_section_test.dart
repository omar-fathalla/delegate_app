import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:delegate_app/features/marketing_search/presentation/widgets/delegate_search_section.dart';

void main() {
  testWidgets('DelegateSearchSection renders correctly and triggers onSearch', (tester) async {
    final controller = TextEditingController();
    bool searchTriggered = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DelegateSearchSection(
            controller: controller,
            onSearch: () {
              searchTriggered = true;
            },
          ),
        ),
      ),
    );

    // Verify UI elements
    expect(find.text('البحث عن مندوب'), findsOneWidget);
    expect(find.text('رقم الموبايل'), findsOneWidget);
    expect(find.text('أدخل رقم الموبايل (مثال: 01012345678)'), findsOneWidget);
    expect(find.text('بحث عن المندوب'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(ElevatedButton), findsOneWidget);

    // Enter text
    await tester.enterText(find.byType(TextField), '01012345678');
    expect(controller.text, '01012345678');

    // Tap search button
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();

    // Verify callback
    expect(searchTriggered, isTrue);
  });
}
