import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// Material 3 design tokens for the HR screens (web and mobile) — TAS-113.
///
/// Use these instead of raw numbers and hex colors so every HR screen
/// follows one type scale, four corner radii, and the user's chosen seed
/// color (Settings › App color offers 5 seeds).

/// Font sizes from the M3 type scale.
///
/// The web never goes below 12; mobile keeps M3 `labelSmall` (11).
abstract final class HrFont {
  /// M3 labelSmall. Captions, table sub-lines, badges.
  static const double labelSmall = kIsWeb ? 12 : 11;

  /// M3 labelMedium / bodySmall. Chips, secondary text.
  static const double labelMedium = 12;

  /// M3 bodyMedium / labelLarge / titleSmall. Body text, buttons, rows.
  static const double body = 14;

  /// M3 titleMedium / bodyLarge. Card titles, section headers.
  static const double titleMedium = 16;

  /// M3 titleLarge. Page titles, dialog titles.
  static const double titleLarge = 22;

  /// M3 headlineSmall. Big KPI numbers.
  static const double headlineSmall = 24;
}

/// The four corner radii used across HR screens.
abstract final class HrRadius {
  /// Chips, small badges, tags.
  static const double chip = 8;

  /// Cards, tables, list tiles, panels.
  static const double card = 12;

  /// Buttons and segmented controls.
  static const double button = 20;

  /// Search bars, pills, dialogs, side sheets.
  static const double pill = 28;
}

/// Semantic status colors that follow the current theme.
///
/// M3 has no success/warning roles, so they are generated with
/// [ColorScheme.fromSeed] from a fixed green and amber for the current
/// brightness. Danger uses the theme's own `error` roles.
@immutable
class HrStatusColors {
  const HrStatusColors._({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.danger,
    required this.onDanger,
    required this.dangerContainer,
    required this.onDangerContainer,
  });

  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;
  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color onWarningContainer;
  final Color danger;
  final Color onDanger;
  final Color dangerContainer;
  final Color onDangerContainer;

  static const Color _successSeed = Color(0xFF2E7D32);
  static const Color _warningSeed = Color(0xFFE65100);

  static final Map<(Brightness, int), HrStatusColors> _cache = {};

  static HrStatusColors of(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final key = (scheme.brightness, scheme.error.toARGB32());
    return _cache.putIfAbsent(key, () {
      final ok = ColorScheme.fromSeed(
        seedColor: _successSeed,
        brightness: scheme.brightness,
      );
      final warn = ColorScheme.fromSeed(
        seedColor: _warningSeed,
        brightness: scheme.brightness,
      );
      return HrStatusColors._(
        success: ok.primary,
        onSuccess: ok.onPrimary,
        successContainer: ok.primaryContainer,
        onSuccessContainer: ok.onPrimaryContainer,
        warning: warn.primary,
        onWarning: warn.onPrimary,
        warningContainer: warn.primaryContainer,
        onWarningContainer: warn.onPrimaryContainer,
        danger: scheme.error,
        onDanger: scheme.onError,
        dangerContainer: scheme.errorContainer,
        onDangerContainer: scheme.onErrorContainer,
      );
    });
  }
}
