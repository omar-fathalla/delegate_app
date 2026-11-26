import 'package:material_ui/material_ui.dart';

import 'motion.dart';
import 'tokens.dart';
import 'typography.dart';
import 'widgets/tooltips.dart';

/// Builds the single Material 3 theme used by the app and the playground.
///
/// Light and dark come from the same seed ([TashilColors.seed]). Component
/// themes here are the only place component defaults are changed: screens use
/// plain M3 widgets and inherit these.
abstract final class TashilTheme {
  /// Bundled Arabic font (assets/fonts/cairo, OFL). Bundled, not fetched, so
  /// the app looks the same offline on first launch.
  static const fontFamily = 'Cairo';

  /// [contrast] follows the M3 contrast levels; the app passes
  /// [TashilContrast.high] for `highContrastTheme` (system setting) and
  /// may offer medium and high as an in-app choice.
  ///
  /// [seed] is the scheme's source colour (Tashil green by default; see
  /// `color_schemes.dart` for the store colour, wallpaper and baseline
  /// sources). [variant] is the Material Color Utilities algorithm:
  /// tonal spot by default, fidelity to stay close to a brand colour.
  static ThemeData light({
    TashilContrast contrast = TashilContrast.standard,
    Color seed = TashilColors.seed,
    DynamicSchemeVariant variant = DynamicSchemeVariant.tonalSpot,
  }) => _build(Brightness.light, contrast, seed, variant);
  static ThemeData dark({
    TashilContrast contrast = TashilContrast.standard,
    Color seed = TashilColors.seed,
    DynamicSchemeVariant variant = DynamicSchemeVariant.tonalSpot,
  }) => _build(Brightness.dark, contrast, seed, variant);

  static ThemeData _build(
    Brightness brightness,
    TashilContrast contrast,
    Color seed,
    DynamicSchemeVariant variant,
  ) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      contrastLevel: contrast.level,
      dynamicSchemeVariant: variant,
    );
    final base = ThemeData(
      colorScheme: scheme,
      brightness: brightness,
      fontFamily: fontFamily,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );
    // M3 type scale with Arabic's "medium" language height; emphasized
    // styles and editorial tokens go in the theme extension.
    const languageHeight = TashilLanguageHeight.medium;
    final text = TashilTypeScale.baseline(base.textTheme, languageHeight);
    final emphasized = TashilTypeScale.emphasized(
      base.textTheme,
      languageHeight,
    );

    const buttonMin = Size(64, TashilSizes.minTouch);
    final buttonText = WidgetStatePropertyAll(text.labelLarge);

    return base.copyWith(
      textTheme: text,
      primaryTextTheme: TashilTypeScale.baseline(
        base.primaryTextTheme,
        languageHeight,
      ),
      extensions: [
        TashilSemanticColors.forBrightness(brightness, contrast: contrast),
        TashilTypeExtension(
          emphasized: emphasized,
          editorial: TashilEditorial.from(text, emphasized),
          languageHeight: languageHeight,
        ),
      ],
      appBarTheme: const AppBarTheme(centerTitle: false),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(buttonMin),
          textStyle: buttonText,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(buttonMin),
          textStyle: buttonText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(buttonMin),
          textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(buttonMin),
          textStyle: buttonText,
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      tooltipTheme: plainTooltipTheme,
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsetsDirectional.symmetric(
          horizontal: TashilSpacing.lg,
        ),
      ),
      dividerTheme: const DividerThemeData(space: 1),
      // Cairo is wider than Roboto: at 360dp the stock headlineLarge cuts
      // "الخميس، 26 نوفمبر". One step down keeps the whole date visible.
      // M3 2024 progress indicators: gap between indicator and track, stop
      // dot at the end of determinate linear ones, rounded ends. Flutter
      // marks the flag deprecated only because false becomes the default
      // later; it is the official opt-in until then.
      // ignore: deprecated_member_use
      progressIndicatorTheme: const ProgressIndicatorThemeData(year2023: false),
      // Same opt-in for the 2024 slider: handle that narrows while pressed,
      // track gap, stop indicators, value label above the handle.
      // ignore: deprecated_member_use
      sliderTheme: const SliderThemeData(year2023: false),
      datePickerTheme: DatePickerThemeData(
        headerHeadlineStyle: text.headlineSmall,
        rangePickerHeaderHeadlineStyle: text.headlineSmall,
      ),
      pageTransitionsTheme: TashilTransitions.pageTransitionsTheme,
    );
  }
}
