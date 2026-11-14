import 'package:delegate_app/config/theme/app_motion.dart';
import 'package:flutter/material.dart';
import 'tashil_button_group.dart';

enum TashilIconButtonVariant {
  standard,
  filled,
  tonal,
  outlined,
  close,
}

/// Official Material Design 3 Circular Icon Button
///
/// Implements standard 40x40dp touch target (or 36x36dp compact for data tables)
/// with official Google Material Icons, circular shape, and M3 Hover Engine.
///
/// Complies with:
/// - Single-Icon Rule
/// - Shaded Close Button Rule (shaded background, subtle border, darkened on hover)
/// - Primary-Derived Hover State Layer
class TashilIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final TashilIconButtonVariant variant;
  final double size;
  final double iconSize;
  final Color? color;
  final Color? backgroundColor;

  const TashilIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.variant = TashilIconButtonVariant.tonal,
    this.size = 36.0,
    this.iconSize = 18.0,
    this.color,
    this.backgroundColor,
  });

  const TashilIconButton.filled({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.size = 36.0,
    this.iconSize = 18.0,
    this.color,
    this.backgroundColor,
  }) : variant = TashilIconButtonVariant.filled;

  const TashilIconButton.tonal({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.size = 36.0,
    this.iconSize = 18.0,
    this.color,
    this.backgroundColor,
  }) : variant = TashilIconButtonVariant.tonal;

  const TashilIconButton.outlined({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.size = 36.0,
    this.iconSize = 18.0,
    this.color,
    this.backgroundColor,
  }) : variant = TashilIconButtonVariant.outlined;

  const TashilIconButton.standard({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.size = 36.0,
    this.iconSize = 18.0,
    this.color,
    this.backgroundColor,
  }) : variant = TashilIconButtonVariant.standard;

  /// Shaded Close Button ('X') per M3 Rule:
  /// Mandatory circular shaded background (surfaceContainerHighest) + subtle border,
  /// with prominent darkening on hover/press.
  const TashilIconButton.close({
    super.key,
    this.icon = Icons.close_rounded,
    this.onPressed,
    this.tooltip = 'إغلاق',
    this.size = 32.0,
    this.iconSize = 16.0,
    this.color,
    this.backgroundColor,
  }) : variant = TashilIconButtonVariant.close;

  @override
  State<TashilIconButton> createState() => _TashilIconButtonState();
}

class _TashilIconButtonState extends State<TashilIconButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isEnabled = widget.onPressed != null;

    Color bg;
    Color fg;
    Border? border;

    switch (widget.variant) {
      case TashilIconButtonVariant.filled:
        final base = widget.backgroundColor ?? colorScheme.primary;
        bg = _isPressed
            ? Color.lerp(base, Colors.black, 0.18)!
            : _isHovered
                ? colorScheme.primaryDarkenedHover
                : base;
        fg = widget.color ?? colorScheme.onPrimary;
        break;

      case TashilIconButtonVariant.tonal:
        final base = widget.backgroundColor ??
            colorScheme.surfaceContainerHighest.withValues(alpha: 0.55);
        bg = _isPressed
            ? Color.lerp(base, colorScheme.primary, 0.20)!
            : _isHovered
                ? Color.lerp(base, colorScheme.primary, 0.12)!
                : base;
        fg = widget.color ?? colorScheme.onSurfaceVariant;
        break;

      case TashilIconButtonVariant.outlined:
        bg = _isHovered
            ? colorScheme.primaryHoverStateLayer
            : Colors.transparent;
        fg = widget.color ?? colorScheme.primary;
        border = Border.all(
          color: _isHovered
              ? colorScheme.primaryHoverBorder
              : colorScheme.outlineVariant.withValues(alpha: 0.6),
          width: 1.0,
        );
        break;

      case TashilIconButtonVariant.standard:
        bg = _isHovered
            ? colorScheme.primaryHoverStateLayer
            : Colors.transparent;
        fg = widget.color ?? colorScheme.onSurfaceVariant;
        break;

      case TashilIconButtonVariant.close:
        // Shaded Close Button Rule
        final base = widget.backgroundColor ??
            colorScheme.surfaceContainerHighest;
        bg = _isPressed
            ? Color.lerp(base, Colors.black, 0.22)!
            : _isHovered
                ? Color.lerp(base, Colors.black, 0.12)!
                : base;
        fg = widget.color ?? colorScheme.onSurface;
        border = Border.all(
          color: _isHovered
              ? colorScheme.outline
              : colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: 0.9,
        );
        break;
    }

    if (!isEnabled) {
      bg = colorScheme.onSurface.withValues(alpha: 0.05);
      fg = colorScheme.onSurface.withValues(alpha: 0.38);
      border = null;
    }

    Widget button = MouseRegion(
      cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: isEnabled ? (_) => setState(() => _isPressed = true) : null,
        onTapUp: isEnabled ? (_) => setState(() => _isPressed = false) : null,
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: AppMotionDurations.short4,
          curve: AppMotionCurves.standardDefaultEffects,
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
            border: border,
          ),
          child: Center(
            child: Icon(
              widget.icon,
              size: widget.iconSize,
              color: fg,
            ),
          ),
        ),
      ),
    );

    if (widget.tooltip != null && widget.tooltip!.isNotEmpty) {
      button = Tooltip(
        message: widget.tooltip!,
        waitDuration: AppMotionDurations.medium4,
        child: button,
      );
    }

    return button;
  }
}
