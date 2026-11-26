import 'package:material_ui/material_ui.dart';

import '../tokens.dart';

/// M3 Expressive menus (m3.material.io/components/menus/guidelines).
///
/// Built only from Flutter's official menu parts ([MenuAnchor],
/// [MenuItemButton], [SubmenuButton], [CheckboxMenuButton]). What Flutter
/// doesn't draw yet, and this adds:
/// * **gaps**: groups of items on separate rounded surfaces with a small
///   gap, instead of one surface with dividers (use one or two gaps; no
///   gaps in scrolling menus, use dividers there);
/// * **color styles**: `standard` (surface based) and `vibrant` (tertiary,
///   for few, prominent menus);
/// * **selected item**: rounded highlight with a check.
///
/// The button that opens the menu shows a pressed state while it is open
/// ([MenuButton]).

enum MenuColorStyle { standard, vibrant }

/// Colours for a menu style, shared by the container and its items.
class _MenuColors {
  _MenuColors(ColorScheme s, MenuColorStyle style)
    : container = style == MenuColorStyle.vibrant
          ? s.tertiaryContainer
          : s.surfaceContainerLow,
      content = style == MenuColorStyle.vibrant
          ? s.onTertiaryContainer
          : s.onSurface,
      selected = style == MenuColorStyle.vibrant
          ? s.tertiary
          : s.tertiaryContainer,
      onSelected = style == MenuColorStyle.vibrant
          ? s.onTertiary
          : s.onTertiaryContainer;

  final Color container;
  final Color content;
  final Color selected;
  final Color onSelected;
}

/// Menu children split into groups separated by gaps. Pass the result as
/// [MenuAnchor.menuChildren] together with [groupedMenuStyle].
List<Widget> groupedMenuChildren(
  BuildContext context,
  List<List<Widget>> groups, {
  MenuColorStyle style = MenuColorStyle.standard,
}) {
  final c = _MenuColors(Theme.of(context).colorScheme, style);
  return [
    for (var i = 0; i < groups.length; i++)
      Padding(
        padding: EdgeInsets.only(top: i == 0 ? 0 : 2),
        child: Material(
          color: c.container,
          elevation: 3,
          shadowColor: Theme.of(context).colorScheme.shadow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(TashilRadius.large),
          ),
          clipBehavior: Clip.antiAlias,
          child: IconTheme.merge(
            data: IconThemeData(color: c.content),
            child: DefaultTextStyle.merge(
              style: TextStyle(color: c.content),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: TashilSpacing.xs),
                child: IntrinsicWidth(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: groups[i],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
  ];
}

/// The container of a grouped menu is transparent: each group draws its
/// own surface.
const groupedMenuStyle = MenuStyle(
  backgroundColor: WidgetStatePropertyAll(Colors.transparent),
  surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
  shadowColor: WidgetStatePropertyAll(Colors.transparent),
  elevation: WidgetStatePropertyAll(0),
  padding: WidgetStatePropertyAll(EdgeInsets.zero),
);

/// A menu item in the M3 Expressive look: optional supporting text and
/// trailing text, rounded highlight + check when [selected], and shown
/// disabled (not removed) when [onPressed] is null.
class MenuOption extends StatelessWidget {
  const MenuOption({
    super.key,
    required this.label,
    this.icon,
    this.supportingText,
    this.trailingText,
    this.selected = false,
    this.style = MenuColorStyle.standard,
    this.closeOnActivate = true,
    required this.onPressed,
  });

  final String label;
  final IconData? icon;
  final String? supportingText;
  final String? trailingText;
  final bool selected;
  final MenuColorStyle style;
  final bool closeOnActivate;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = _MenuColors(Theme.of(context).colorScheme, style);
    final text = Theme.of(context).textTheme;
    final fg = selected ? c.onSelected : c.content;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: TashilSpacing.xs),
      child: Semantics(
        selected: selected,
        child: MenuItemButton(
          onPressed: onPressed,
          closeOnActivate: closeOnActivate,
          leadingIcon: selected
              ? Icon(Icons.check, color: fg)
              : icon == null
              ? null
              : Icon(icon),
          trailingIcon: trailingText == null
              ? null
              : Text(trailingText!, style: text.labelLarge),
          style: ButtonStyle(
            minimumSize: const WidgetStatePropertyAll(
              Size(112, TashilSizes.minTouch),
            ),
            backgroundColor: WidgetStatePropertyAll(
              selected ? c.selected : Colors.transparent,
            ),
            foregroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.disabled)
                  ? c.content.withValues(alpha: 0.38)
                  : fg,
            ),
            iconColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.disabled)
                  ? c.content.withValues(alpha: 0.38)
                  : fg,
            ),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(TashilRadius.medium),
              ),
            ),
          ),
          child: supportingText == null
              ? Text(label)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label),
                    Text(
                      supportingText!,
                      style: text.bodySmall?.copyWith(
                        color: fg.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// An icon button that opens a menu and stays pressed (selected) while the
/// menu is open, as M3 asks. Choosing an item does not change the icon.
class MenuButton extends StatefulWidget {
  const MenuButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.menuChildren,
    this.style,
  });

  final IconData icon;
  final String tooltip;
  final List<Widget> menuChildren;
  final MenuStyle? style;

  @override
  State<MenuButton> createState() => _MenuButtonState();
}

class _MenuButtonState extends State<MenuButton> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      style: widget.style,
      onOpen: () => setState(() => _open = true),
      onClose: () => setState(() => _open = false),
      menuChildren: widget.menuChildren,
      builder: (context, controller, _) => IconButton(
        tooltip: widget.tooltip,
        isSelected: _open,
        style: IconButton.styleFrom(
          // Pressed look while open; same icon.
          backgroundColor: _open
              ? Theme.of(context).colorScheme.secondaryContainer
              : null,
        ),
        icon: Icon(widget.icon),
        onPressed: () => _open ? controller.close() : controller.open(),
      ),
    );
  }
}

/// Opens a menu where the person long-pressed (touch) or right-clicked
/// (mouse): the M3 **context menu**.
class ContextMenuRegion extends StatefulWidget {
  const ContextMenuRegion({
    super.key,
    required this.menuChildren,
    required this.child,
    this.style,
  });

  final List<Widget> menuChildren;
  final Widget child;
  final MenuStyle? style;

  @override
  State<ContextMenuRegion> createState() => _ContextMenuRegionState();
}

class _ContextMenuRegionState extends State<ContextMenuRegion> {
  final _controller = MenuController();

  void _open(Offset local) => _controller.open(position: local);

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      controller: _controller,
      style: widget.style,
      menuChildren: widget.menuChildren,
      child: GestureDetector(
        onLongPressStart: (d) => _open(d.localPosition),
        onSecondaryTapDown: (d) => _open(d.localPosition),
        child: widget.child,
      ),
    );
  }
}
