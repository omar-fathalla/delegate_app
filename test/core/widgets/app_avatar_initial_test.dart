import 'package:delegate_app/config/theme/app_theme.dart';
import 'package:delegate_app/core/widgets/app_avatar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// TAS-384: the initial in the header avatar sat off centre because Cairo's
/// tall Arabic line height added space above the glyph. The letter's box must
/// now sit in the middle of the circle.
void main() {
  testWidgets('the Arabic initial is centred in the avatar', (t) async {
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Center(
              child: AppAvatar(fallbackText: 'مندوب تجريبي', radius: 20),
            ),
          ),
        ),
      ),
    );

    final avatar = t.getRect(find.byType(AppAvatar));
    final letter = find.text('م');
    expect(letter, findsOneWidget);
    final box = t.getRect(letter);
    // Arabic initials are lifted by a share of the letter size (20 * 0.85).
    const lift = 20 * 0.85 * AppAvatar.arabicLift;
    expect(box.center.dy, moreOrLessEquals(avatar.center.dy - lift, epsilon: 1));
    expect((box.center.dx - avatar.center.dx).abs(), lessThan(1.0));

    final style = t.widget<Text>(letter).style!;
    expect(style.height, 1);
    expect(style.leadingDistribution, TextLeadingDistribution.even);
  });

  testWidgets('a Latin initial is not lifted', (t) async {
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        home: const Scaffold(
          body: Center(child: AppAvatar(fallbackText: 'test', radius: 20)),
        ),
      ),
    );
    final avatar = t.getRect(find.byType(AppAvatar));
    final box = t.getRect(find.text('T'));
    expect(box.center.dy, moreOrLessEquals(avatar.center.dy, epsilon: 1));
  });
}
