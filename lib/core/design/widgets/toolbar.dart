import 'package:material_ui/material_ui.dart';

import '../tokens.dart';

/// One action in a [TashilToolbar].
class ToolbarAction {
  const ToolbarAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.selected = false,
  });

  final IconData icon;

  /// Tooltip and screen reader label: what it does, not what it looks like.
  final String label;
  final VoidCallback? onPressed;

  /// Toggle actions (bold, grid view) show their state.
  final bool selected;
}

/// The M3 Expressive floating toolbar, for the scaffold's **rail
/// regions** (m3.material.io/foundations/layout/scaffold/rails): actions
/// for the current screen, floating above the content.
///
/// * Compact: horizontal, in the bottom rail, above the navigation bar
///   ([AdaptiveNavigationScaffold.toolbar] places it).
/// * Medium and up: vertical, in the trailing rail beside the panes.
///
/// Hand-built: Flutter has no toolbar component yet (Compose has
/// `HorizontalFloatingToolbar` / `VerticalFloatingToolbar`). Pill shaped
/// surface-container with level 3 elevation, 48dp icon buttons, 8dp
/// padding. Keep it to a few actions; more go in an overflow menu.
class TashilToolbar extends StatelessWidget {
  const TashilToolbar({
    super.key,
    required this.actions,
    this.axis = Axis.horizontal,
  });

  final List<ToolbarAction> actions;
  final Axis axis;

  @override
  Widget build(BuildContext context) {
    assert(actions.isNotEmpty && actions.length <= 6, 'Few actions only');
    final scheme = Theme.of(context).colorScheme;
    final buttons = [
      for (final a in actions)
        IconButton(
          tooltip: a.label,
          isSelected: a.selected,
          onPressed: a.onPressed,
          icon: Icon(a.icon),
        ),
    ];
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Material(
        color: scheme.surfaceContainer,
        elevation: 3,
        shadowColor: scheme.shadow,
        shape: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.all(TashilSpacing.sm),
          child: Flex(
            direction: axis,
            mainAxisSize: MainAxisSize.min,
            spacing: TashilSpacing.xs,
            children: buttons,
          ),
        ),
      ),
    );
  }
}
