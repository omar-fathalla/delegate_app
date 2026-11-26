import 'package:delegate_app/config/theme/app_theme.dart';
import 'package:delegate_app/core/design/widgets/summary_card.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// P-07 SummaryCard (TAS-387): the content fills the card. The icon sits on
/// primary / onPrimary, the trailing value is on the end side, and the facts
/// share the full width equally.
void main() {
  Future<void> pump(WidgetTester t, {bool muted = false}) async {
    t.view.physicalSize = const Size(400, 400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SummaryCard(
              icon: Icons.storefront_rounded,
              title: 'فرع المعادي',
              subtitle: 'سلسلة تجريبية',
              trailingValue: '07:45',
              trailingCaption: 'المدة',
              trailingMuted: muted,
              labels: const [
                SummaryLabel('نشط', container: Colors.transparent, onContainer: Colors.black),
              ],
              facts: const [
                SummaryFact(icon: Icons.login_rounded, label: 'الدخول', value: '09:02'),
                SummaryFact(icon: Icons.logout_rounded, label: 'الخروج', value: '16:47'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('trailing value on the end side (left in RTL), facts share the width', (t) async {
    await pump(t);
    final card = t.getRect(find.byType(Card));
    final value = t.getRect(find.byKey(const Key('summary_card_trailing_value')));
    final title = t.getRect(find.text('فرع المعادي'));
    expect(value.center.dx, lessThan(title.center.dx));
    final inFact = t.getRect(find.text('الدخول'));
    final outFact = t.getRect(find.text('الخروج'));
    // First fact on the start (right) half, second on the end (left) half.
    expect(inFact.center.dx, greaterThan(card.center.dx));
    expect(outFact.center.dx, lessThan(card.center.dx));
    expect(find.byType(Divider), findsOneWidget);
    expect(find.text('نشط'), findsOneWidget);
  });

  testWidgets('icon on primary / onPrimary; muted value is onSurfaceVariant', (t) async {
    await pump(t, muted: true);
    final cs = AppTheme.lightTheme().colorScheme;
    final icon = t.widget<Icon>(find.byIcon(Icons.storefront_rounded));
    expect(icon.color, cs.onPrimary);
    final value = t.widget<Text>(find.byKey(const Key('summary_card_trailing_value')));
    expect(value.style?.color, cs.onSurfaceVariant);
  });
}
