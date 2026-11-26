import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:delegate_app/features/photo_permission/presentation/widgets/company_name_with_code.dart';
import 'package:delegate_app/features/photo_permission/presentation/pages/supervisor_permissions_screen.dart';

void main() {
  group('CompanyNameWithCode Widget Tests', () {
    testWidgets('renders company name on top and company code on bottom by default', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CompanyNameWithCode(
              organizationUID: 'org1',
              companyUID: 'comp1',
              companyName: 'سيفين بوت',
              companyCode: 5579,
            ),
          ),
        ),
      );

      expect(find.text('سيفين بوت'), findsOneWidget);
      expect(find.text('كود: 5579'), findsOneWidget);

      final codeWidget = tester.widget<Text>(find.text('كود: 5579'));
      expect(codeWidget.style?.fontSize, 10.5);
      expect(codeWidget.maxLines, 1);
      expect(codeWidget.overflow, TextOverflow.ellipsis);
    });
  });

  group('ExpandableBranchText Widget Tests', () {
    final branches = ['فرع النزهة', 'فرع سموحة', 'فرع محرم بك'];

    testWidgets('is completely collapsed by default and does not render branch text', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExpandableBranchText(branchNames: branches),
          ),
        ),
      );

      // Should show summary chip without unicode arrows
      expect(find.text('الفروع المعتمدة (3)'), findsOneWidget);
      expect(find.text('عرض المزيد'), findsOneWidget);
      expect(find.byIcon(Icons.expand_more_rounded), findsOneWidget);

      // Should NOT render branch names when collapsed
      expect(find.text('فرع النزهة، فرع سموحة، فرع محرم بك'), findsNothing);

      // Tap to expand
      await tester.tap(find.text('عرض المزيد'));
      await tester.pumpAndSettle();

      // Now branch names are visible
      expect(find.text('فرع النزهة، فرع سموحة، فرع محرم بك'), findsOneWidget);
      expect(find.text('عرض أقل'), findsOneWidget);

      // Tap to collapse
      await tester.tap(find.text('عرض أقل'));
      await tester.pumpAndSettle();

      // Branch names hidden again
      expect(find.text('فرع النزهة، فرع سموحة، فرع محرم بك'), findsNothing);
      expect(find.text('عرض المزيد'), findsOneWidget);
    });

    testWidgets('handles empty branches list cleanly without expand button', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ExpandableBranchText(branchNames: []),
          ),
        ),
      );

      expect(find.text('لا توجد فروع معتمدة'), findsOneWidget);
      expect(find.text('عرض المزيد'), findsNothing);
    });
  });

  group('Photo Permission Card Header Responsive Tests', () {
    testWidgets('renders cleanly on narrow 320dp screen without overflow', (tester) async {
      tester.view.physicalSize = const Size(320 * 2, 640 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Expanded(
                        child: CompanyNameWithCode(
                          organizationUID: 'org1',
                          companyUID: 'comp1',
                          companyName: 'شركة تجريبية ذات اسم طويل جداً لتجربة العرض',
                          companyCode: 5579,
                          twoLines: true,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            child: const Text('مقبول'),
                          ),
                          const SizedBox(height: 4),
                          const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.verified_user_rounded, size: 13),
                              SizedBox(width: 4),
                              Text('Technical Support'),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('شركة تجريبية ذات اسم طويل جداً لتجربة العرض'), findsOneWidget);
      expect(find.text('كود: 5579'), findsOneWidget);
      expect(find.text('Technical Support'), findsOneWidget);
    });
  });
}
