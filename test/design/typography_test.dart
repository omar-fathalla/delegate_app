import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:delegate_app/core/design/app_theme.dart';
import 'package:delegate_app/core/design/typography.dart';

List<TextStyle> _all(TextTheme t) => [
  t.displayLarge!,
  t.displayMedium!,
  t.displaySmall!,
  t.headlineLarge!,
  t.headlineMedium!,
  t.headlineSmall!,
  t.titleLarge!,
  t.titleMedium!,
  t.titleSmall!,
  t.bodyLarge!,
  t.bodyMedium!,
  t.bodySmall!,
  t.labelLarge!,
  t.labelMedium!,
  t.labelSmall!,
];

void main() {
  final theme = TashilTheme.light();
  final base = theme.textTheme;
  final emph = theme.extension<TashilTypeExtension>()!.emphasized;

  test('M3 sizes; Arabic medium language height (7% taller lines)', () {
    const g = Typography.englishLike2021;
    final geo = _all(g);
    final ours = _all(base);
    for (var i = 0; i < 15; i++) {
      expect(ours[i].fontSize, geo[i].fontSize);
      expect(ours[i].height, closeTo(geo[i].height! * 1.07, 0.0001));
    }
    // 57/64 display large becomes about 68 in Arabic.
    expect(
      base.displayLarge!.fontSize! * base.displayLarge!.height!,
      closeTo(68.5, 0.5),
    );
  });

  test('emphasized: same size and line, one weight step heavier', () {
    final b = _all(base);
    final e = _all(emph);
    for (var i = 0; i < 15; i++) {
      expect(e[i].fontSize, b[i].fontSize);
      expect(e[i].height, b[i].height);
      expect(e[i].letterSpacing, b[i].letterSpacing);
      expect(e[i].fontWeight!.value, greaterThan(b[i].fontWeight!.value));
    }
    // From the M3 Expressive tokens.
    expect(emph.displayLarge!.fontWeight, FontWeight.w500);
    expect(emph.titleMedium!.fontWeight, FontWeight.w700);
    expect(emph.labelLarge!.fontWeight, FontWeight.w700);
    expect(emph.bodyLarge!.fontWeight, FontWeight.w500);
  });

  test('variable weight axis pinned; brand and plain typefaces; fallback', () {
    for (final s in [..._all(base), ..._all(emph)]) {
      expect(s.fontVariations, [
        FontVariation.weight(s.fontWeight!.value.toDouble()),
      ]);
      expect(s.fontFamilyFallback, TashilType.fallback);
    }
    expect(base.displayLarge!.fontFamily, TashilType.brandFont);
    expect(base.bodyMedium!.fontFamily, TashilType.plainFont);
  });

  test('editorial hero number: tabular, weight follows the value', () {
    final e = theme.extension<TashilTypeExtension>()!.editorial;
    expect(
      e.heroNumber.fontFeatures,
      contains(const FontFeature.tabularFigures()),
    );
    expect(e.heroNumberAt(0).fontVariations!.single.value, 400);
    expect(e.heroNumberAt(1).fontVariations!.single.value, 900);
  });

  testWidgets('links are primary, underlined and announced as links', (
    t,
  ) async {
    final s = t.ensureSemantics();
    var taps = 0;
    await t.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(body: LinkText('شروط', onTap: () => taps++)),
      ),
    );
    final text = t.widget<Text>(find.text('شروط'));
    expect(text.style!.decoration, TextDecoration.underline);
    expect(text.style!.color, theme.colorScheme.primary);
    expect(
      t.getSemantics(find.byType(LinkText)),
      matchesSemantics(
        isLink: true,
        hasTapAction: true,
        isFocusable: true,
        hasFocusAction: true,
      ),
    );
    await t.tap(find.text('شروط'));
    expect(taps, 1);
    s.dispose();
  });
}
