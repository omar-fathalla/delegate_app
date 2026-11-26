import 'package:material_ui/material_ui.dart';

import '../../core/design/app_theme.dart';
import '../../core/design/tokens.dart';
import 'app_motion.dart';

/// App entry point for the Material 3 theme (TAS-348).
///
/// Everything comes from the Tashil design system in `lib/core/design/`
/// (copied from m3-kit): every colour role generated from one seed (no
/// hand-picked tones; user decision 2026-11-26, replacing the pinned
/// "approved" values of 47d05fb0), the Cairo variable font with the M3 type
/// scale, semantic success/warning colours, shapes, spacing and motion.
/// Screens must read colours from `Theme.of(context).colorScheme` (or
/// `TashilSemanticColors.of(context)`) and text from `textTheme`, never hex
/// values or hand-written font sizes.
///
/// The seed stays the delegate app's purple by default; the person can pick
/// another one in settings ([ThemeCubit]), and the roles follow it.
class AppTheme {
  static ThemeData lightTheme([Color? seedColor]) =>
      _app(TashilTheme.light(seed: seedColor ?? TashilColors.seed));

  static ThemeData darkTheme([Color? seedColor]) =>
      _app(TashilTheme.dark(seed: seedColor ?? TashilColors.seed));

  /// Used by `MaterialApp.highContrastTheme`, so the system "high contrast"
  /// setting switches every role to about 7:1 text contrast.
  static ThemeData highContrastLightTheme([Color? seedColor]) => _app(
    TashilTheme.light(
      seed: seedColor ?? TashilColors.seed,
      contrast: TashilContrast.high,
    ),
  );

  static ThemeData highContrastDarkTheme([Color? seedColor]) => _app(
    TashilTheme.dark(
      seed: seedColor ?? TashilColors.seed,
      contrast: TashilContrast.high,
    ),
  );

  /// Two app-wide choices kept from before the design system:
  /// * one page transition for every route, the same one the go_router pages
  ///   use ([AppMotionPage]), so a push never mixes two transitions;
  /// * sheets show the M3 drag handle from the theme (51 screens open sheets
  ///   and rely on it).
  static ThemeData _app(ThemeData theme) => theme.copyWith(
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: M3PageTransitionsBuilder(),
        TargetPlatform.iOS: M3PageTransitionsBuilder(),
        TargetPlatform.macOS: M3PageTransitionsBuilder(),
      },
    ),
    bottomSheetTheme: theme.bottomSheetTheme.copyWith(showDragHandle: true),
  );
}
