// ignore: unnecessary_import
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:delegate_app/config/theme/app_motion.dart';
import 'package:google_fonts/google_fonts.dart';

import 'color_schemes.dart';

class AppTheme {
  // Base configuration to prevent code duplication (Clean Code)
  static ThemeData _baseTheme(
    ColorScheme colorScheme,
    TextTheme baseTextTheme,
  ) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      textTheme: baseTextTheme,

      // Inputs (Spacing & White Space)
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),

      // Buttons (Typography & Touch Targets)
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: baseTextTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      // Navigation (Micro-interactions & State Management)
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surfaceContainer,
        elevation: 0,
        indicatorColor: colorScheme.secondaryContainer,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return baseTextTheme.labelSmall!.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.bold,
            );
          }
          return baseTextTheme.labelSmall!.copyWith(
            color: colorScheme.onSurfaceVariant,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: colorScheme.onSecondaryContainer);
          }
          return IconThemeData(color: colorScheme.onSurfaceVariant);
        }),
      ),

      // App Bar
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surfaceContainer,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 2,
        centerTitle: false,
        titleTextStyle: baseTextTheme.titleMedium?.copyWith(
          color: colorScheme.onSurface,
          fontSize: 15,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.2,
        ),
        shape: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.35),
            width: 0.8,
          ),
        ),
      ),

      // Scaffold Background
      scaffoldBackgroundColor: colorScheme.surfaceContainerLowest,

      // Dialogs & Cards
      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainerLow,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      dialogTheme: DialogThemeData(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(28)),
        ),
        elevation: 3,
        backgroundColor: colorScheme.surfaceContainer,
      ),

      // Tooltips (Material Design 3 Rounded Style)
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        textStyle: baseTextTheme.bodySmall?.copyWith(
          color: colorScheme.onSurface,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      ),

      // Material Design 3 Motion Page Transitions
      // One transition for every route (go_router pages use the same
      // AppMotionTransitions.sharedAxisX), so nothing overlaps mid-push.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: M3PageTransitionsBuilder(),
          TargetPlatform.iOS: M3PageTransitionsBuilder(),
          TargetPlatform.macOS: M3PageTransitionsBuilder(),
        },
      ),
    );
  }

  static ThemeData lightTheme([Color? seedColor]) {
    final color = seedColor ?? AppColorSchemes.seedColors[0];
    var colorScheme = ColorScheme.fromSeed(
      seedColor: color,
      brightness: Brightness.light,
    );
    // Approved neutral light surfaces (home_v2n). Applied to every seed;
    // brand roles are pinned only for the default #6750A4 seed.
    colorScheme = colorScheme.copyWith(
      surface: const Color(0xFFFDF8F8),
      surfaceBright: const Color(0xFFFDF8F8),
      onSurface: const Color(0xFF1C1B1C),
      surfaceDim: const Color(0xFFDDD9D9),
      surfaceContainerLowest: const Color(0xFFFFFFFF),
      surfaceContainerLow: const Color(0xFFF7F3F2),
      surfaceContainer: const Color(0xFFF1EDED),
      surfaceContainerHigh: const Color(0xFFEBE7E7),
      surfaceContainerHighest: const Color(0xFFE6E1E1),
      onSurfaceVariant: const Color(0xFF48464B),
      // ignore: deprecated_member_use
      surfaceVariant: const Color(0xFFE6E1E7),
      outline: const Color(0xFF79767B),
      outlineVariant: const Color(0xFFCAC5CB),
      inverseSurface: const Color(0xFF313030),
      onInverseSurface: const Color(0xFFF4F0F0),
    );
    if (color.toARGB32() == 0xFF6750A4) {
      colorScheme = colorScheme.copyWith(
        primary: const Color(0xFF6750A4),
        onPrimary: const Color(0xFFFFFFFF),
        primaryContainer: const Color(0xFFE9DDFF),
        onPrimaryContainer: const Color(0xFF22005D),
        inversePrimary: const Color(0xFFCFBCFF),
        secondary: const Color(0xFF625B70),
        secondaryContainer: const Color(0xFFE8DEF8),
        onSecondaryContainer: const Color(0xFF1E192B),
        tertiary: const Color(0xFF7E5260),
        tertiaryContainer: const Color(0xFFFFD9E3),
        onTertiaryContainer: const Color(0xFF31101D),
        error: const Color(0xFFBA1A1A),
        errorContainer: const Color(0xFFFFDAD6),
        onErrorContainer: const Color(0xFF410002),
      );
    }
    final baseTextTheme = GoogleFonts.cairoTextTheme();

    return _baseTheme(colorScheme, baseTextTheme);
  }

  static ThemeData darkTheme([Color? seedColor]) {
    final color = seedColor ?? AppColorSchemes.seedColors[0];
    final colorScheme = ColorScheme.fromSeed(
      seedColor: color,
      brightness: Brightness.dark,
    );
    final baseTextTheme = GoogleFonts.cairoTextTheme().apply(
      bodyColor: colorScheme.onSurface,
      displayColor: colorScheme.onSurface,
    );

    return _baseTheme(colorScheme, baseTextTheme);
  }
}
