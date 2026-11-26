import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../motion.dart';
import '../tokens.dart';

/// One action in a [FabMenu].
class FabMenuItem {
  const FabMenuItem({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
}

/// M3 Expressive **FAB menu** (m3.material.io/components/fab-menu): a FAB
/// that opens a short list (2-6) of related actions. Flutter's Material
/// library does not ship it yet.
///
/// Accessibility (m3.material.io/components/fab-menu/accessibility):
/// * every item is at least 48dp; items are 56dp tall.
/// * on open, focus lands on the close button, then moves top to bottom
///   through the items; Esc closes.
/// * the toggle is announced as a button with an expanded/collapsed state.
/// * items scroll behind the close button on short screens; the close
///   button is never covered.
///
/// Motion: the toggle morphs with the fast spatial spring, items enter with
/// the default spatial spring, staggered from the bottom.
class FabMenu extends StatefulWidget {
  const FabMenu({
    super.key,
    required this.items,
    this.icon = Icons.add,
    this.tooltip = 'قائمة الإجراءات',
  }) : assert(items.length >= 2 && items.length <= 6);

  final List<FabMenuItem> items;

  /// Icon of the closed FAB.
  final IconData icon;

  /// Accessibility label of the toggle button.
  final String tooltip;

  @override
  State<FabMenu> createState() => _FabMenuState();
}

class _FabMenuState extends State<FabMenu> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController.unbounded(
    vsync: this,
  );
  final _toggleFocus = FocusNode(debugLabel: 'FabMenu toggle');
  bool _open = false;

  @override
  void dispose() {
    _c.dispose();
    _toggleFocus.dispose();
    super.dispose();
  }

  void _setOpen(bool open) {
    if (open == _open) return;
    setState(() => _open = open);
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final target = open ? 1.0 : 0.0;
    if (reduce) {
      _c.value = target;
    } else {
      _c.animateWith(
        SpringSimulation(
          TashilSpring.defaultSpatial.description,
          _c.value,
          target,
          _c.velocity,
        ),
      );
    }
    // Initial focus on the close button when the menu opens.
    if (open) _toggleFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final n = widget.items.length;

    Widget item(int i) {
      final it = widget.items[i];
      // Bottom item (closest to the FAB) enters first.
      final order = n - 1 - i;
      final start = order * 0.08;
      return AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          final p = ((_c.value - start) / (1 - start)).clamp(-0.2, 1.2);
          return Opacity(
            opacity: TashilMotion.unit(p * 1.5),
            child: Transform.translate(
              offset: Offset(0, (1 - p) * 24),
              child: Transform.scale(
                scale: 0.8 + 0.2 * p,
                alignment: AlignmentDirectional.centerEnd.resolve(
                  Directionality.of(context),
                ),
                child: child,
              ),
            ),
          );
        },
        child: FocusTraversalOrder(
          order: NumericFocusOrder(1.0 + i),
          child: Padding(
            padding: const EdgeInsets.only(bottom: TashilSpacing.xs),
            child: Material(
              color: scheme.primaryContainer,
              shape: const StadiumBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () {
                  _setOpen(false);
                  it.onPressed();
                },
                child: Container(
                  height: 56,
                  constraints: const BoxConstraints(minWidth: 48),
                  padding: const EdgeInsetsDirectional.only(
                    start: TashilSpacing.lg,
                    end: TashilSpacing.xl,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(it.icon, color: scheme.onPrimaryContainer),
                      const SizedBox(width: TashilSpacing.sm),
                      Text(
                        it.label,
                        style: text.titleMedium?.copyWith(
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final toggle = FocusTraversalOrder(
      order: const NumericFocusOrder(0),
      child: Semantics(
        button: true,
        expanded: _open,
        label: widget.tooltip,
        excludeSemantics: true,
        child: Tooltip(
          message: widget.tooltip,
          child: AnimatedContainer(
            duration: TashilMotion.scaled(context, TashilMotion.fast.duration),
            curve: TashilMotion.fast.curve,
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: _open ? scheme.primary : scheme.primaryContainer,
              borderRadius: BorderRadius.circular(
                _open ? 28 : TashilRadius.large,
              ),
              boxShadow: [
                BoxShadow(
                  color: scheme.shadow.withValues(alpha: 0.25),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                focusNode: _toggleFocus,
                customBorder: const CircleBorder(),
                onTap: () => _setOpen(!_open),
                child: Center(
                  child: AnimatedRotation(
                    turns: _open ? 0.125 : 0,
                    duration: TashilMotion.scaled(
                      context,
                      TashilMotion.fast.duration,
                    ),
                    curve: TashilMotion.fast.curve,
                    child: Icon(
                      _open ? Icons.add : widget.icon,
                      color: _open
                          ? scheme.onPrimary
                          : scheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => _setOpen(false),
      },
      child: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Items live in their own scroll view so on short screens they
            // scroll behind the close button instead of covering it.
            Flexible(
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, child) => _c.value <= 0.001 && !_open
                    ? const SizedBox.shrink()
                    : child!,
                child: SingleChildScrollView(
                  reverse: true,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [for (var i = 0; i < n; i++) item(i)],
                  ),
                ),
              ),
            ),
            const SizedBox(height: TashilSpacing.sm),
            toggle,
          ],
        ),
      ),
    );
  }
}
