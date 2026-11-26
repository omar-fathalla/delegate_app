import 'package:material_ui/material_ui.dart';

/// Colors of a selected stat (KPI) card that works as a filter on HR web
/// (TAS-154, TAS-185).
///
/// Every HR web page marks the selected card with the theme's primary
/// container, so the selection looks the same everywhere. The card's status
/// color stays on its icon or number only. Mobile pages keep their own
/// status tint and do not use this.
@immutable
class HrSelectedCardColors {
  /// Card fill: `primaryContainer`.
  final Color background;

  /// Border, shadow and accent marks (for example a check badge): `primary`.
  final Color accent;

  /// Title, subtitle and other text on the card: `onPrimaryContainer`.
  final Color foreground;

  /// Content drawn on [accent], for example the check icon: `onPrimary`.
  final Color onAccent;

  const HrSelectedCardColors({
    required this.background,
    required this.accent,
    required this.foreground,
    required this.onAccent,
  });

  factory HrSelectedCardColors.of(ColorScheme cs) => HrSelectedCardColors(
    background: cs.primaryContainer,
    accent: cs.primary,
    foreground: cs.onPrimaryContainer,
    onAccent: cs.onPrimary,
  );
}
