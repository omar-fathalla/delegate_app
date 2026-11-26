import 'package:delegate_app/config/theme/app_theme.dart';
import 'package:delegate_app/core/widgets/app_snack_bar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// TAS-352: AppSnackBar goes through the design system's snackbar: text
/// only, no icon or status fill, one at a time, gone after 4 seconds.
void main() {
  Future<BuildContext> pump(WidgetTester t) async {
    late BuildContext ctx;
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        home: Scaffold(
          body: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    return ctx;
  }

  for (final (name, show) in [
    ('error', AppSnackBar.showError),
    ('success', AppSnackBar.showSuccess),
    ('info', AppSnackBar.showInfo),
  ]) {
    testWidgets('$name: text only, no icon, no status fill', (t) async {
      final ctx = await pump(t);
      show(ctx, '✅ اتحفظ');
      await t.pump();
      final bar = t.widget<SnackBar>(find.byType(SnackBar));
      expect(bar.backgroundColor, isNull);
      expect(find.text('اتحفظ'), findsOneWidget);
      expect(
        find.descendant(of: find.byType(SnackBar), matching: find.byType(Icon)),
        findsNothing,
      );
      expect(bar.duration, const Duration(seconds: 4));
    });
  }

  testWidgets('one at a time: a new message replaces the old', (t) async {
    final ctx = await pump(t);
    AppSnackBar.showInfo(ctx, 'الأولى');
    await t.pump();
    AppSnackBar.showError(ctx, 'التانية');
    await t.pumpAndSettle();
    expect(find.text('الأولى'), findsNothing);
    expect(find.text('التانية'), findsOneWidget);
  });
}
