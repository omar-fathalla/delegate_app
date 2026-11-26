import 'package:material_ui/material_ui.dart';

/// Typography that follows m3.material.io/styles/typography (overview,
/// fonts, type scale and tokens, applying type, editorial treatments).
///
/// * One type scale, five roles (display, headline, title, body, label) in
///   three sizes: 15 **baseline** styles (Flutter's `textTheme`) and 15
///   **emphasized** styles ([TashilType.emphasized]) from the M3 Expressive
///   tokens (androidx Compose `TypeScaleTokens`): same size, line height
///   and tracking, one weight step heavier.
/// * **Brand and plain typefaces**: display and headline use
///   [brandFont], the rest [plainFont]. Both are Cairo today (Arabic and
///   Latin in one variable font, bundled for offline use).
/// * **Language height**: Arabic is in M3's "medium" category (about 7%
///   taller than Latin), so line heights grow by [TashilLanguageHeight].
/// * Variable weight axis pinned to each style's weight.
/// * Fallback: Roboto, then Noto Sans, for glyphs Cairo lacks.
abstract final class TashilType {
  /// Typeface for large expressive styles (display, headline).
  static const brandFont = 'Cairo';

  /// Typeface for readable small styles (title, body, label).
  static const plainFont = 'Cairo';

  /// M3 font fallback order after our own font.
  static const fallback = ['Roboto', 'Noto Sans', 'Noto Sans Arabic'];

  /// The 15 emphasized styles. Use them for selection, primary actions,
  /// unread items and headlines; Material components don't use them by
  /// default.
  static TextTheme emphasized(BuildContext context) =>
      Theme.of(context).extension<TashilTypeExtension>()!.emphasized;

  /// Editorial tokens for hero moments.
  static TashilEditorial editorial(BuildContext context) =>
      Theme.of(context).extension<TashilTypeExtension>()!.editorial;
}

/// M3 language height categories (Aug 2026). Multiplies line heights.
enum TashilLanguageHeight {
  /// Latin, Cyrillic, Greek, Hebrew.
  small(1.0),

  /// Arabic, Chinese, Hindi, Thai and most others. Our default.
  medium(1.07),

  /// Burmese, Telugu.
  large(1.30),

  /// Nastaliq.
  extraLarge(2.0);

  const TashilLanguageHeight(this.factor);
  final double factor;
}

/// Builds the baseline and emphasized text themes from Flutter's official
/// M3 geometry (`Typography.englishLike2021`, the 2021 type scale tokens).
abstract final class TashilTypeScale {
  /// Baseline weights from the M3 tokens.
  static const _baseline = <String, FontWeight>{
    'display': FontWeight.w400,
    'headline': FontWeight.w400,
    'titleLarge': FontWeight.w400,
    'title': FontWeight.w500,
    'body': FontWeight.w400,
    'label': FontWeight.w500,
  };

  /// Emphasized weights from the M3 Expressive tokens.
  static const _emphasized = <String, FontWeight>{
    'display': FontWeight.w500,
    'headline': FontWeight.w500,
    'titleLarge': FontWeight.w500,
    'title': FontWeight.w700,
    'body': FontWeight.w500,
    'label': FontWeight.w700,
  };

  static FontWeight _weight(Map<String, FontWeight> w, String name) {
    if (name == 'titleLarge') return w['titleLarge']!;
    for (final role in ['display', 'headline', 'title', 'body', 'label']) {
      if (name.startsWith(role)) return w[role]!;
    }
    throw ArgumentError(name);
  }

  static TextStyle _style(
    String name,
    TextStyle? colorAndFamily,
    TextStyle geometry,
    FontWeight weight,
    TashilLanguageHeight height,
  ) {
    final brand = name.startsWith('display') || name.startsWith('headline');
    return (colorAndFamily ?? const TextStyle()).copyWith(
      fontFamily: brand ? TashilType.brandFont : TashilType.plainFont,
      fontFamilyFallback: TashilType.fallback,
      fontSize: geometry.fontSize,
      height: geometry.height! * height.factor,
      letterSpacing: geometry.letterSpacing,
      fontWeight: weight,
      // Cairo is variable: pin the wght axis so bold is really bold.
      fontVariations: [FontVariation.weight(weight.value.toDouble())],
      textBaseline: geometry.textBaseline,
      leadingDistribution: geometry.leadingDistribution,
    );
  }

  static TextTheme _build(
    TextTheme colors,
    TashilLanguageHeight height,
    Map<String, FontWeight> weights,
  ) {
    const g = Typography.englishLike2021;
    TextStyle s(String n, TextStyle? c, TextStyle? geo) =>
        _style(n, c, geo!, _weight(weights, n), height);
    return TextTheme(
      displayLarge: s('displayLarge', colors.displayLarge, g.displayLarge),
      displayMedium: s('displayMedium', colors.displayMedium, g.displayMedium),
      displaySmall: s('displaySmall', colors.displaySmall, g.displaySmall),
      headlineLarge: s('headlineLarge', colors.headlineLarge, g.headlineLarge),
      headlineMedium: s(
        'headlineMedium',
        colors.headlineMedium,
        g.headlineMedium,
      ),
      headlineSmall: s('headlineSmall', colors.headlineSmall, g.headlineSmall),
      titleLarge: s('titleLarge', colors.titleLarge, g.titleLarge),
      titleMedium: s('titleMedium', colors.titleMedium, g.titleMedium),
      titleSmall: s('titleSmall', colors.titleSmall, g.titleSmall),
      bodyLarge: s('bodyLarge', colors.bodyLarge, g.bodyLarge),
      bodyMedium: s('bodyMedium', colors.bodyMedium, g.bodyMedium),
      bodySmall: s('bodySmall', colors.bodySmall, g.bodySmall),
      labelLarge: s('labelLarge', colors.labelLarge, g.labelLarge),
      labelMedium: s('labelMedium', colors.labelMedium, g.labelMedium),
      labelSmall: s('labelSmall', colors.labelSmall, g.labelSmall),
    );
  }

  /// The 15 baseline styles.
  static TextTheme baseline(TextTheme colors, TashilLanguageHeight h) =>
      _build(colors, h, _baseline);

  /// The 15 emphasized styles.
  static TextTheme emphasized(TextTheme colors, TashilLanguageHeight h) =>
      _build(colors, h, _emphasized);
}

/// Tokens for editorial treatments: standalone, type-led hero moments
/// (end-of-day sales, a goal reached). Only for those moments, never for
/// labels or plain information, and one treatment per layout.
@immutable
class TashilEditorial {
  const TashilEditorial({required this.heroNumber, required this.heroCaption});

  /// A big figure: display large, heavy, tabular digits, tight line.
  final TextStyle heroNumber;

  /// The line above or below the figure.
  final TextStyle heroCaption;

  /// Weight for [heroNumber] at [t] from 0 to 1 (the variable `wght` axis
  /// can follow a value, like sales growing towards a target).
  TextStyle heroNumberAt(double t) {
    final w = 400 + (900 - 400) * t.clamp(0.0, 1.0);
    return heroNumber.copyWith(
      fontWeight: FontWeight.lerp(FontWeight.w400, FontWeight.w900, t),
      fontVariations: [FontVariation.weight(w)],
    );
  }

  static TashilEditorial from(TextTheme baseline, TextTheme emphasized) =>
      TashilEditorial(
        heroNumber: baseline.displayLarge!.copyWith(
          fontWeight: FontWeight.w800,
          fontVariations: const [FontVariation.weight(800)],
          height: 1.1,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
        heroCaption: emphasized.titleLarge!,
      );

  TashilEditorial lerp(TashilEditorial other, double t) => TashilEditorial(
    heroNumber: TextStyle.lerp(heroNumber, other.heroNumber, t)!,
    heroCaption: TextStyle.lerp(heroCaption, other.heroCaption, t)!,
  );
}

class TashilTypeExtension extends ThemeExtension<TashilTypeExtension> {
  const TashilTypeExtension({
    required this.emphasized,
    required this.editorial,
    required this.languageHeight,
  });

  final TextTheme emphasized;
  final TashilEditorial editorial;
  final TashilLanguageHeight languageHeight;

  @override
  TashilTypeExtension copyWith({
    TextTheme? emphasized,
    TashilEditorial? editorial,
    TashilLanguageHeight? languageHeight,
  }) => TashilTypeExtension(
    emphasized: emphasized ?? this.emphasized,
    editorial: editorial ?? this.editorial,
    languageHeight: languageHeight ?? this.languageHeight,
  );

  @override
  TashilTypeExtension lerp(TashilTypeExtension? other, double t) {
    if (other == null) return this;
    return TashilTypeExtension(
      emphasized: TextTheme.lerp(emphasized, other.emphasized, t),
      editorial: editorial.lerp(other.editorial, t),
      languageHeight: t < 0.5 ? languageHeight : other.languageHeight,
    );
  }
}

/// Hyperlink text (M3: primary colour, or tertiary for a quieter link,
/// always underlined). Announced as a link.
class LinkText extends StatelessWidget {
  const LinkText(
    this.text, {
    super.key,
    required this.onTap,
    this.quiet = false,
    this.style,
  });

  final String text;
  final VoidCallback onTap;

  /// Uses tertiary instead of primary.
  final bool quiet;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final color = quiet ? s.tertiary : s.primary;
    return Semantics(
      link: true,
      child: InkWell(
        onTap: onTap,
        child: Text(
          text,
          style: (style ?? Theme.of(context).textTheme.bodyMedium)?.copyWith(
            color: color,
            decoration: TextDecoration.underline,
            decorationColor: color,
          ),
        ),
      ),
    );
  }
}
