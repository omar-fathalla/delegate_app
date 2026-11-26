import 'package:material_ui/material_ui.dart';

import '../motion.dart';

/// M3 Expressive **button groups**
/// (m3.material.io/components/button-groups), which Flutter's Material
/// library does not ship yet. Built from plain Material + InkWell so it
/// follows the app theme.
///
/// * [ButtonGroupVariant.standard]: separate buttons with a gap. The pressed
///   button widens and its neighbours make room; its corners morph from
///   round to square.
/// * [ButtonGroupVariant.connected]: buttons touch (2dp gap), outer corners
///   are fully round, inner corners are small. The selected button becomes
///   fully round. This replaces [SegmentedButton], which M3 no longer
///   recommends.
enum ButtonGroupVariant { standard, connected }

/// M3 Expressive button sizes. Height in dp.
enum ButtonGroupSize {
  xs(32, 18, 4, 12),
  s(40, 12, 8, 16),
  m(56, 8, 8, 24),
  l(96, 8, 16, 48),
  xl(136, 8, 20, 64);

  const ButtonGroupSize(
    this.height,
    this.standardGap,
    this.innerRadius,
    this.padding,
  );

  final double height;

  /// Space between buttons in a standard group.
  final double standardGap;

  /// Inner corner radius in a connected group.
  final double innerRadius;

  /// Horizontal padding inside each button.
  final double padding;

  double get iconSize => switch (this) {
    xs || s => 20,
    m => 24,
    l => 32,
    xl => 40,
  };

  TextStyle? textStyle(TextTheme t) => switch (this) {
    xs || s => t.labelLarge,
    m => t.titleMedium,
    l => t.headlineSmall,
    xl => t.headlineLarge,
  };
}

class ButtonGroupItem<T> {
  const ButtonGroupItem({
    required this.value,
    this.label,
    this.icon,
    this.tooltip,
  }) : assert(label != null || icon != null);

  final T value;
  final String? label;
  final IconData? icon;

  /// Required for icon-only items (accessibility).
  final String? tooltip;
}

class ButtonGroup<T> extends StatefulWidget {
  const ButtonGroup({
    super.key,
    required this.items,
    this.variant = ButtonGroupVariant.standard,
    this.size = ButtonGroupSize.s,
    this.selected,
    this.onSelectionChanged,
    this.onPressed,
    this.multiSelect = false,
    this.selectionRequired = true,
    this.expand = false,
  });

  final List<ButtonGroupItem<T>> items;
  final ButtonGroupVariant variant;
  final ButtonGroupSize size;

  /// Selected values. Null makes the group plain actions ([onPressed]).
  final Set<T>? selected;
  final ValueChanged<Set<T>>? onSelectionChanged;
  final ValueChanged<T>? onPressed;
  final bool multiSelect;

  /// When true, the last selected button cannot be unselected.
  final bool selectionRequired;

  /// Stretch to the available width, buttons sharing it equally.
  final bool expand;

  @override
  State<ButtonGroup<T>> createState() => _ButtonGroupState<T>();
}

class _ButtonGroupState<T> extends State<ButtonGroup<T>> {
  int? _pressed;

  // Shape and width morph: M3 Expressive fast spatial spring.
  static const _spring = TashilMotion.fast;

  bool get _connected => widget.variant == ButtonGroupVariant.connected;

  void _tap(T value) {
    widget.onPressed?.call(value);
    final selected = widget.selected;
    final onChanged = widget.onSelectionChanged;
    if (selected == null || onChanged == null) return;
    final next = {...selected};
    if (next.contains(value)) {
      if (widget.selectionRequired && next.length == 1) return;
      next.remove(value);
    } else {
      if (!widget.multiSelect) next.clear();
      next.add(value);
    }
    onChanged(next);
  }

  BorderRadiusDirectional _radius(int i, bool isSelected, bool isPressed) {
    final h = widget.size.height;
    final full = Radius.circular(h / 2);
    // Pressed buttons morph toward a square shape.
    final square = Radius.circular(widget.size.innerRadius * 0.75);
    if (!_connected) {
      return BorderRadiusDirectional.all(
        isPressed ? Radius.circular(widget.size.innerRadius + 4) : full,
      );
    }
    if (isSelected && !isPressed) return BorderRadiusDirectional.all(full);
    final inner = isPressed ? square : Radius.circular(widget.size.innerRadius);
    final first = i == 0;
    final last = i == widget.items.length - 1;
    return BorderRadiusDirectional.only(
      topStart: first ? full : inner,
      bottomStart: first ? full : inner,
      topEnd: last ? full : inner,
      bottomEnd: last ? full : inner,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final size = widget.size;
    final gap = _connected ? 2.0 : size.standardGap;
    // How much the pressed button grows and its neighbours shrink.
    final grow = _connected ? 0.0 : size.padding * 0.3;

    final children = <Widget>[];
    for (var i = 0; i < widget.items.length; i++) {
      final item = widget.items[i];
      final isSelected = widget.selected?.contains(item.value) ?? false;
      final isPressed = _pressed == i;
      final neighbourPressed =
          _pressed != null && (_pressed == i - 1 || _pressed == i + 1);
      // Icon-only buttons are square: padding centres the icon.
      final basePad = item.label == null
          ? (size.height - size.iconSize) / 2
          // Expanded buttons share the width: keep labels from truncating.
          : (widget.expand ? size.padding / 2 : size.padding);
      final pad =
          basePad + (isPressed ? grow : 0) - (neighbourPressed ? grow / 2 : 0);

      final (Color bg, Color fg) = isSelected
          ? (scheme.primary, scheme.onPrimary)
          : (scheme.secondaryContainer, scheme.onSecondaryContainer);

      final showCheck = isSelected && _connected && item.icon == null;
      final content = Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (item.icon != null || showCheck)
            Icon(
              showCheck ? Icons.check : item.icon,
              size: size.iconSize,
              color: fg,
            ),
          if ((item.icon != null || showCheck) && item.label != null)
            SizedBox(width: size.padding / 3),
          if (item.label != null)
            Flexible(
              child: Text(
                item.label!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: size.textStyle(text)?.copyWith(color: fg),
              ),
            ),
        ],
      );

      final radius = _radius(i, isSelected, isPressed);
      Widget button = AnimatedContainer(
        duration: TashilMotion.scaled(context, _spring.duration),
        curve: _spring.curve,
        height: size.height,
        constraints: BoxConstraints(minWidth: size.height),
        padding: EdgeInsetsDirectional.symmetric(horizontal: pad),
        decoration: BoxDecoration(color: bg, borderRadius: radius),
        child: Center(child: content),
      );
      button = Material(
        type: MaterialType.transparency,
        child: InkWell(
          customBorder: RoundedRectangleBorder(borderRadius: radius),
          onTap: () => _tap(item.value),
          onHighlightChanged: (down) =>
              setState(() => _pressed = down ? i : null),
          child: button,
        ),
      );
      button = Semantics(
        button: true,
        selected: widget.selected == null ? null : isSelected,
        label: item.label ?? item.tooltip,
        child: button,
      );
      if (item.tooltip != null) {
        button = Tooltip(message: item.tooltip!, child: button);
      }
      // Keep the 48dp touch target for XS buttons.
      if (size.height < 48) {
        button = ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Center(child: button),
        );
      }
      if (i > 0) children.add(SizedBox(width: gap));
      children.add(widget.expand ? Expanded(child: button) : button);
    }

    return Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      children: children,
    );
  }
}
