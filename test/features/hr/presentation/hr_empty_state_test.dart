import 'package:delegate_app/features/hr/presentation/widgets/hr_empty_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
  home: Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(body: child),
  ),
);

void main() {
  testWidgets('shows icon and title only when optional parts are null', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const HrEmptyState(icon: Icons.inbox_rounded, title: 'لا توجد بيانات'),
      ),
    );

    expect(find.text('لا توجد بيانات'), findsOneWidget);
    final icon = tester.widget<Icon>(find.byIcon(Icons.inbox_rounded));
    expect(icon.size, 48);
    final context = tester.element(find.byType(HrEmptyState));
    expect(icon.color, Theme.of(context).colorScheme.onSurfaceVariant);
    expect(find.byType(Text), findsOneWidget);
  });

  testWidgets('shows message and action, and the action is tappable', (
    tester,
  ) async {
    var tapped = 0;
    await tester.pumpWidget(
      _host(
        HrEmptyState(
          icon: Icons.inbox_rounded,
          title: 'لا توجد بيانات',
          message: 'ستظهر البيانات هنا عند إضافتها.',
          action: TextButton(
            onPressed: () => tapped++,
            child: const Text('إضافة'),
          ),
        ),
      ),
    );

    final context = tester.element(find.byType(HrEmptyState));
    final theme = Theme.of(context);
    final title = tester.widget<Text>(find.text('لا توجد بيانات'));
    expect(title.style, theme.textTheme.titleMedium);
    final message = tester.widget<Text>(
      find.text('ستظهر البيانات هنا عند إضافتها.'),
    );
    expect(message.style?.fontSize, theme.textTheme.bodyMedium?.fontSize);
    expect(message.style?.color, theme.colorScheme.onSurfaceVariant);

    await tester.tap(find.text('إضافة'));
    expect(tapped, 1);
  });
}
