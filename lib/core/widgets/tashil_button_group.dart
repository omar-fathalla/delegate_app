import 'package:flutter/material.dart';

/// Extension for M3 Dynamic Primary-Derived Hover Engine
extension M3HoverColorScheme on ColorScheme {
  /// Darken primary by 10% in Light Mode, lighten by 12% in Dark Mode
  Color get primaryDarkenedHover => brightness == Brightness.light
      ? Color.lerp(primary, Colors.black, 0.10)!
      : Color.lerp(primary, Colors.white, 0.12)!;

  /// Interaction state layer of 8% primary for unselected buttons and cards
  Color get primaryHoverStateLayer => primary.withValues(alpha: 0.08);

  /// Border color transitions to 48% active primary on hover
  Color get primaryHoverBorder => primary.withValues(alpha: 0.48);
}

/// Item definition for [TashilConnectedButtonGroup]
class TashilConnectedButtonItem<T> {
  final T value;
  final String label;
  final IconData? icon;
  final Color? activeColor;
  final Color? activeForegroundColor;

  const TashilConnectedButtonItem({
    required this.value,
    required this.label,
    this.icon,
    this.activeColor,
    this.activeForegroundColor,
  });
}

/// Official Material Design 3 Expressive Connected Button Group
///
/// Designed as a continuous capsule track (height 42-44dp, radius 24dp)
/// with a floating inner thumb (height 35dp, radius 17.5dp) animating in 220ms
/// with [Curves.easeInOutCubic].
/// Complies with:
/// - Single-Icon Rule (maximum 1 icon per button, no emojis combined with icon widgets)
/// - M3 Dynamic Hover State Layer
/// - RTL Directionality awareness
class TashilConnectedButtonGroup<T> extends StatelessWidget {
  final List<TashilConnectedButtonItem<T>> items;
  final T selectedValue;
  final ValueChanged<T> onSelected;
  final double height;
  final bool isScrollable;
  final double? width;

  const TashilConnectedButtonGroup({
    super.key,
    required this.items,
    required this.selectedValue,
    required this.onSelected,
    this.height = 44.0,
    this.isScrollable = false,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final content = Container(
      height: height,
      width: width,
      padding: const EdgeInsets.all(4.0),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24.0),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.35),
          width: 1.0,
        ),
      ),
      child: Row(
        mainAxisSize: isScrollable || width == null ? MainAxisSize.min : MainAxisSize.max,
        children: items.map((item) {
          final isSelected = item.value == selectedValue;
          final buttonWidget = _TashilConnectedButtonSegment<T>(
            item: item,
            isSelected: isSelected,
            onTap: () => onSelected(item.value),
          );

          if (isScrollable || width == null) {
            return buttonWidget;
          }
          return Expanded(child: buttonWidget);
        }).toList(),
      ),
    );

    if (isScrollable) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: content,
      );
    }

    return content;
  }
}

class _TashilConnectedButtonSegment<T> extends StatefulWidget {
  final TashilConnectedButtonItem<T> item;
  final bool isSelected;
  final VoidCallback onTap;

  const _TashilConnectedButtonSegment({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_TashilConnectedButtonSegment<T>> createState() =>
      _TashilConnectedButtonSegmentState<T>();
}

class _TashilConnectedButtonSegmentState<T>
    extends State<_TashilConnectedButtonSegment<T>> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final item = widget.item;
    final isSelected = widget.isSelected;

    final defaultActiveColor = colorScheme.primary;
    final activeBg = item.activeColor ?? defaultActiveColor;
    final activeFg = item.activeForegroundColor ??
        (activeBg == colorScheme.primary
            ? colorScheme.onPrimary
            : Colors.white);

    final unselectedFg = colorScheme.onSurfaceVariant;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOutCubic,
          height: 35.0,
          padding: const EdgeInsets.symmetric(horizontal: 14.0),
          decoration: BoxDecoration(
            color: isSelected
                ? (_isHovered
                    ? (item.activeColor != null
                        ? Color.lerp(activeBg, Colors.black, 0.08)!
                        : colorScheme.primaryDarkenedHover)
                    : activeBg)
                : (_isHovered
                    ? colorScheme.primaryHoverStateLayer
                    : Colors.transparent),
            borderRadius: BorderRadius.circular(17.5),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: activeBg.withValues(alpha: 0.22),
                      blurRadius: 4,
                      offset: const Offset(0, 1.5),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (item.icon != null) ...[
                Icon(
                  item.icon,
                  size: 15.0,
                  color: isSelected ? activeFg : unselectedFg,
                ),
                const SizedBox(width: 6.0),
              ],
              Text(
                item.label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: isSelected ? activeFg : unselectedFg,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  fontSize: 12.0,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
