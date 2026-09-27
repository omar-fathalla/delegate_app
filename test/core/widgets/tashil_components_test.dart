import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:delegate_app/core/widgets/tashil_button_group.dart';
import 'package:delegate_app/core/widgets/tashil_icon_button.dart';

void main() {
  group('TashilConnectedButtonGroup Widget Tests', () {
    testWidgets('renders items with single-icon rule and triggers callback',
        (tester) async {
      String selected = 'all';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return TashilConnectedButtonGroup<String>(
                  selectedValue: selected,
                  onSelected: (val) {
                    setState(() => selected = val);
                  },
                  items: const [
                    TashilConnectedButtonItem<String>(
                      value: 'all',
                      label: 'الكل (10)',
                      icon: Icons.people_alt_outlined,
                    ),
                    TashilConnectedButtonItem<String>(
                      value: 'present',
                      label: 'حاضرون (5)',
                      icon: Icons.check_circle_rounded,
                      activeColor: Color(0xFF2E7D32),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('الكل (10)'), findsOneWidget);
      expect(find.text('حاضرون (5)'), findsOneWidget);
      expect(find.byIcon(Icons.people_alt_outlined), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);

      await tester.tap(find.text('حاضرون (5)'));
      await tester.pumpAndSettle();

      expect(selected, equals('present'));
    });
  });

  group('TashilIconButton Widget Tests', () {
    testWidgets('renders circular M3 button with correct icon and tooltip',
        (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TashilIconButton.tonal(
              icon: Icons.call_outlined,
              tooltip: 'اتصال هاتفي',
              onPressed: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.call_outlined), findsOneWidget);

      await tester.tap(find.byIcon(Icons.call_outlined));
      await tester.pumpAndSettle();

      expect(tapped, isTrue);
    });

    testWidgets('shaded close button conforms to M3 rules', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TashilIconButton.close(),
          ),
        ),
      );

      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    });
  });
}
