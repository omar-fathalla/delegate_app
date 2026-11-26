import 'package:material_ui/material_ui.dart';

/// Tashil design tokens. Every screen reads spacing, radii, sizes and colours
/// from here (or from `Theme.of(context)`), never from magic numbers.
///
/// The rules behind these values are documented in `docs/design-system.md`.
abstract final class TashilColors {
  /// M3 seed colour. The whole light and dark [ColorScheme] is generated from
  /// it with [ColorScheme.fromSeed]; do not hand-pick tonal colours.
  static const seed = Color(0xFF6750A4);

  /// Semantic colours M3 does not ship (M3 only has `error`). Use them through
  /// [TashilSemanticColors], which turns each into a tonal set for light,
  /// dark and every contrast level. Like `error` they are static: they keep
  /// their meaning (green, orange) and are not pulled towards the seed.
  static const success = Color(0xFF2E7D32);
  static const warning = Color(0xFFB26A00);
}

/// The three M3 contrast levels (May 2025). Every colour role, including
/// [TashilSemanticColors], is regenerated for the chosen level, so screens
/// that only use roles in their intended pairs support all three.
enum TashilContrast {
  /// Default: mixed contrast that keeps the visual hierarchy.
  standard(0),

  /// At least 3:1 everywhere (outline variant too), for people who need
  /// more contrast but find high contrast uncomfortable.
  medium(0.5),

  /// About 7:1 for text and icons; also used when the system asks for high
  /// contrast (`MaterialApp.highContrastTheme`).
  high(1);

  const TashilContrast(this.level);

  /// Value for `ColorScheme.fromSeed(contrastLevel:)`.
  final double level;
}

/// WCAG contrast ratio between two colours (1 to 21).
double contrastRatio(Color a, Color b) {
  final x = a.computeLuminance();
  final y = b.computeLuminance();
  final (hi, lo) = x > y ? (x, y) : (y, x);
  return (hi + 0.05) / (lo + 0.05);
}

/// 4dp grid. Use these instead of literal paddings.
abstract final class TashilSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;

  /// Horizontal page margin on compact (phone / SUNMI V3) screens.
  static const page = 16.0;
}

/// M3 shape scale (m3.material.io/styles/shape/corner-radius-scale).
abstract final class TashilRadius {
  static const none = 0.0;
  static const extraSmall = 4.0;
  static const small = 8.0;
  static const medium = 12.0;
  static const large = 16.0;
  static const extraLarge = 28.0;
  static const full = 999.0;
}

/// Touch and layout sizes tuned for a cashier using the SUNMI V3 one-handed.
/// Divider indents (m3.material.io/components/divider/guidelines).
///
/// * Full width (indent 0): between sections of unrelated content.
/// * Inset: between related items in a list. Equal on both sides by
///   default; in a list with leading icons or images the start lines up
///   with the text, so the divider never cuts under the icon.
abstract final class TashilDividerInset {
  /// Plain inset, both sides. Matches the list tile padding.
  static const both = TashilSpacing.lg;

  /// Start of the text in a [ListTile] with a 24dp leading icon:
  /// padding 16 + icon 24 + gap 16.
  static const afterIcon = TashilSpacing.lg + 24 + TashilSpacing.lg;

  /// Start of the text in a row with a 56dp thumbnail (ProductTile).
  static const afterThumbnail =
      TashilSpacing.lg + TashilSizes.thumbnail + TashilSpacing.lg;
}

abstract final class TashilSizes {
  /// M3 minimum touch target.
  static const minTouch = 48.0;

  /// Primary POS actions (pay, add to cart, confirm) are taller than M3's
  /// default 40dp button so they are hard to miss at the counter.
  static const posButtonHeight = 56.0;

  /// Numeric keypad key height.
  static const keypadKey = 64.0;

  /// Product thumbnail in lists and grids.
  static const thumbnail = 56.0;

  /// Width of the receipt preview: 58mm paper = 384 printer dots.
  static const receiptDots = 384.0;

  /// Start of the medium and expanded breakpoints (M3, previously window
  /// size classes). Same values as [TashilBreakpoint] in layout.dart, which
  /// has all five.
  static const compactMax = 600.0;
  static const mediumMax = 840.0;
}

/// Extra colours that live alongside the M3 [ColorScheme] as a
/// [ThemeExtension], so they switch with light/dark like everything else.
@immutable
class TashilSemanticColors extends ThemeExtension<TashilSemanticColors> {
  const TashilSemanticColors({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
  });

  factory TashilSemanticColors.forBrightness(
    Brightness brightness, {
    TashilContrast contrast = TashilContrast.standard,
  }) {
    ColorScheme from(Color seed) => ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      contrastLevel: contrast.level,
    );
    final s = from(TashilColors.success);
    final w = from(TashilColors.warning);
    return TashilSemanticColors(
      success: s.primary,
      onSuccess: s.onPrimary,
      successContainer: s.primaryContainer,
      onSuccessContainer: s.onPrimaryContainer,
      warning: w.primary,
      onWarning: w.onPrimary,
      warningContainer: w.primaryContainer,
      onWarningContainer: w.onPrimaryContainer,
    );
  }

  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;
  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color onWarningContainer;

  static TashilSemanticColors of(BuildContext context) =>
      Theme.of(context).extension<TashilSemanticColors>()!;

  @override
  TashilSemanticColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? onWarningContainer,
  }) => TashilSemanticColors(
    success: success ?? this.success,
    onSuccess: onSuccess ?? this.onSuccess,
    successContainer: successContainer ?? this.successContainer,
    onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
    warning: warning ?? this.warning,
    onWarning: onWarning ?? this.onWarning,
    warningContainer: warningContainer ?? this.warningContainer,
    onWarningContainer: onWarningContainer ?? this.onWarningContainer,
  );

  @override
  TashilSemanticColors lerp(TashilSemanticColors? other, double t) {
    if (other == null) return this;
    return TashilSemanticColors(
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      successContainer: Color.lerp(
        successContainer,
        other.successContainer,
        t,
      )!,
      onSuccessContainer: Color.lerp(
        onSuccessContainer,
        other.onSuccessContainer,
        t,
      )!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      warningContainer: Color.lerp(
        warningContainer,
        other.warningContainer,
        t,
      )!,
      onWarningContainer: Color.lerp(
        onWarningContainer,
        other.onWarningContainer,
        t,
      )!,
    );
  }
}
