import 'package:delegate_app/config/theme/app_motion.dart';
import 'package:delegate_app/config/theme/app_theme.dart';
import 'package:delegate_app/config/theme/color_schemes.dart';
import 'package:delegate_app/core/design/tokens.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// TAS-348: the app theme is the m3-kit design system (F-01..F-17 of
/// m3-catalog.md), with the delegate app's purple as the default seed.
void main() {
  group('AppTheme comes from the design system', () {
    for (final (name, theme) in [
      ('light', AppTheme.lightTheme()),
      ('dark', AppTheme.darkTheme()),
    ]) {
      test('$name: surfaces, font, semantic colours (F-01, F-04, F-05)', () {
        final cs = theme.colorScheme;
        expect(theme.useMaterial3, isTrue);
        // Body is `surface`, not a container role.
        expect(theme.scaffoldBackgroundColor, cs.surface);
        expect(theme.textTheme.bodyMedium?.fontFamily, 'Cairo');
        expect(theme.extension<TashilSemanticColors>(), isNotNull);
      });

      test('$name: component defaults (C-01, C-08, C-30, C-33)', () {
        // Outlined text fields everywhere.
        expect(theme.inputDecorationTheme.border, isA<OutlineInputBorder>());
        expect(theme.inputDecorationTheme.filled, isNot(true));
        // Floating snackbars above the navigation bar and FAB.
        expect(theme.snackBarTheme.behavior, SnackBarBehavior.floating);
        // 48dp minimum touch target on every button type.
        final min = theme.filledButtonTheme.style?.minimumSize?.resolve({});
        expect(min?.height, TashilSizes.minTouch);
        // No hand-written title size in the app bar.
        expect(theme.appBarTheme.titleTextStyle, isNull);
      });
    }

    test('default seed is the delegate app purple', () {
      expect(TashilColors.seed, AppColorSchemes.seedColors.first);
      expect(
        AppTheme.lightTheme().colorScheme.primary,
        AppTheme.lightTheme(AppColorSchemes.seedColors.first).colorScheme.primary,
      );
    });

    test('another seed from settings changes the roles', () {
      final purple = AppTheme.lightTheme().colorScheme.primary;
      final teal = AppTheme.lightTheme(
        AppColorSchemes.seedColors[1],
      ).colorScheme.primary;
      expect(teal, isNot(purple));
    });

    test('high contrast theme raises text contrast (F-01)', () {
      final standard = AppTheme.lightTheme().colorScheme;
      final high = AppTheme.highContrastLightTheme().colorScheme;
      final s = contrastRatio(standard.onSurfaceVariant, standard.surface);
      final h = contrastRatio(high.onSurfaceVariant, high.surface);
      expect(h, greaterThan(s));
      expect(h, greaterThanOrEqualTo(7));
      expect(AppTheme.highContrastDarkTheme().brightness, Brightness.dark);
    });

    test('one page transition for every route, same as go_router pages', () {
      final builders = AppTheme.lightTheme().pageTransitionsTheme.builders;
      for (final p in [
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
      ]) {
        expect(builders[p], isA<M3PageTransitionsBuilder>());
      }
    });

    test('sheets keep the M3 drag handle from the theme', () {
      expect(AppTheme.lightTheme().bottomSheetTheme.showDragHandle, isTrue);
    });

    test('no hand-picked tones: roles equal ColorScheme.fromSeed (F-01)', () {
      for (final b in Brightness.values) {
        final generated = ColorScheme.fromSeed(
          seedColor: TashilColors.seed,
          brightness: b,
        );
        final theme = b == Brightness.light
            ? AppTheme.lightTheme()
            : AppTheme.darkTheme();
        expect(theme.colorScheme.primary, generated.primary);
        expect(theme.colorScheme.surface, generated.surface);
        expect(
          theme.colorScheme.surfaceContainerLow,
          generated.surfaceContainerLow,
        );
      }
    });
  });
}
