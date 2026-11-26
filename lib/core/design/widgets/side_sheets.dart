import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:material_ui/material_ui.dart';

import '../motion.dart';
import '../tokens.dart';

/// Side sheets that follow m3.material.io/components/side-sheets
/// (guidelines + specs). Flutter has no side sheet widget yet, so these
/// are composed from official parts ([showGeneralDialog], [Material],
/// [AnimatedContainer]) with the spec's sizes and colours.
///
/// * **Modal** (preferred on compact): over a scrim, must be dismissed to
///   use the screen. `surfaceContainerLow`. Can be detached (16dp margins,
///   rounded on all corners).
/// * **Standard** (medium and up): next to the body, which shrinks to make
///   room; both stay usable. `surface`, with an `outlineVariant` edge.
/// * Both: at the end edge (left in Arabic), max 400dp wide, headline with
///   a close button (and an optional back button), content that scrolls
///   vertically only, optional bottom actions after a divider (72dp area,
///   aligned to the start).
/// * Predictive back: drag the modal sheet sideways and it detaches from
///   the top and bottom and scales in the direction of the drag; release
///   past a third of its width or fling to close, otherwise it springs
///   back.
abstract final class SideSheetSpec {
  static const maxWidth = 400.0;
  static const padding = 24.0;
  static const paddingWithIcon = 16.0;
  static const gap = 12.0;
  static const detachedMargin = 16.0;
  static const actionsTop = 16.0;
  static const actionsBottom = 24.0;
}

/// The inside of a side sheet: headline row, scrolling content and
/// optional bottom actions.
class SideSheetPanel extends StatelessWidget {
  const SideSheetPanel({
    super.key,
    required this.title,
    required this.child,
    this.actions = const [],
    this.onClose,
    this.onBack,
  });

  final String title;
  final Widget child;

  /// Bottom buttons, most important first ("تطبيق", then "إلغاء").
  final List<Widget> actions;
  final VoidCallback? onClose;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l = MaterialLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsetsDirectional.fromSTEB(
            onBack == null
                ? SideSheetSpec.padding
                : SideSheetSpec.paddingWithIcon - 4,
            SideSheetSpec.gap,
            SideSheetSpec.gap,
            SideSheetSpec.gap,
          ),
          child: Row(
            children: [
              if (onBack != null) ...[
                IconButton(
                  tooltip: l.backButtonTooltip,
                  icon: const BackButtonIcon(),
                  onPressed: onBack,
                ),
                const SizedBox(width: SideSheetSpec.gap - 8),
              ],
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ),
              if (onClose != null)
                IconButton(
                  tooltip: l.closeButtonTooltip,
                  icon: const Icon(Icons.close),
                  color: scheme.onSurfaceVariant,
                  onPressed: onClose,
                ),
            ],
          ),
        ),
        Expanded(
          // Vertical only: a side sheet never scrolls sideways.
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: SideSheetSpec.padding - TashilSpacing.lg,
            ),
            child: child,
          ),
        ),
        if (actions.isNotEmpty) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              SideSheetSpec.padding,
              SideSheetSpec.actionsTop,
              SideSheetSpec.padding,
              SideSheetSpec.actionsBottom,
            ),
            child: Row(
              children: [
                for (final (i, a) in actions.indexed) ...[
                  if (i > 0) const SizedBox(width: TashilSpacing.sm),
                  a,
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Opens a modal side sheet at the end edge. [builder] gets the sheet's
/// context; pop it with a value to return one.
Future<T?> showSideSheet<T>({
  required BuildContext context,
  required String title,
  required WidgetBuilder builder,
  List<Widget> Function(BuildContext)? actions,
  bool detached = true,
  bool showBack = false,
  double width = SideSheetSpec.maxWidth,
}) {
  final l = MaterialLocalizations.of(context);
  final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: l.modalBarrierDismissLabel,
    barrierColor: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.32),
    transitionDuration: reduce
        ? Duration.zero
        : TashilEasing.emphasizedDecelerate.duration,
    pageBuilder: (c, _, _) => _ModalSideSheet(
      detached: detached,
      width: width,
      panel: (sheetContext) => SideSheetPanel(
        title: title,
        onClose: () => Navigator.pop(sheetContext),
        onBack: showBack ? () => Navigator.pop(sheetContext) : null,
        actions: actions?.call(sheetContext) ?? const [],
        child: builder(sheetContext),
      ),
    ),
    transitionBuilder: (c, a, _, child) {
      final rtl = Directionality.of(c) == TextDirection.rtl;
      final curved = CurvedAnimation(
        parent: a,
        curve: TashilEasing.emphasizedDecelerate.curve,
        reverseCurve: TashilEasing.emphasizedAccelerate.curve,
      );
      // Enter: slide in from the end edge while fading in.
      return SlideTransition(
        position: Tween(
          begin: Offset(rtl ? -1 : 1, 0),
          end: Offset.zero,
        ).animate(curved),
        child: FadeTransition(
          opacity: Tween(begin: 0.4, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _ModalSideSheet extends StatefulWidget {
  const _ModalSideSheet({
    required this.detached,
    required this.width,
    required this.panel,
  });

  final bool detached;
  final double width;
  final WidgetBuilder panel;

  @override
  State<_ModalSideSheet> createState() => _ModalSideSheetState();
}

class _ModalSideSheetState extends State<_ModalSideSheet>
    with SingleTickerProviderStateMixin {
  /// Signed drag progress, -1 to 1 (fraction of the sheet width).
  late final AnimationController _drag = AnimationController.unbounded(
    vsync: this,
  );
  bool _closing = false;

  @override
  void dispose() {
    _drag.dispose();
    super.dispose();
  }

  void _update(DragUpdateDetails d, double width) {
    _drag.value = (_drag.value + d.primaryDelta! / width).clamp(-1.0, 1.0);
  }

  void _end(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (_drag.value.abs() > 1 / 3 || v.abs() > 700) {
      _closing = true;
      Navigator.pop(context);
      return;
    }
    // Cancel: spring back into place.
    final s = TashilSpring.fastSpatial;
    _drag.animateWith(
      SpringSimulation(
        SpringDescription.withDampingRatio(
          mass: 1,
          stiffness: s.stiffness,
          ratio: s.dampingRatio,
        ),
        _drag.value,
        0,
        0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = MediaQuery.sizeOf(context);
    final margin = widget.detached ? SideSheetSpec.detachedMargin : 0.0;
    // Leave a strip of scrim visible to tap on narrow screens.
    final width = math.min(widget.width, size.width - 56 - margin);
    final rtl = Directionality.of(context) == TextDirection.rtl;

    return SafeArea(
      child: Align(
        alignment: AlignmentDirectional.centerEnd,
        child: GestureDetector(
          onHorizontalDragUpdate: (d) => _update(d, width),
          onHorizontalDragEnd: _end,
          child: AnimatedBuilder(
            animation: _drag,
            builder: (context, child) {
              final p = _closing ? 0.0 : _drag.value.abs().clamp(0.0, 1.0);
              // Predictive back: detach from the top and bottom and scale
              // toward the gesture.
              final towardRight = _drag.value > 0;
              return Padding(
                padding: EdgeInsets.symmetric(vertical: 24 * p),
                child: Transform.scale(
                  scale: 1 - 0.1 * p,
                  alignment: towardRight
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: child,
                ),
              );
            },
            child: Padding(
              padding: EdgeInsets.all(margin),
              child: Material(
                color: scheme.surfaceContainerLow,
                elevation: widget.detached ? 1 : 0,
                shadowColor: scheme.shadow,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: widget.detached
                      ? BorderRadius.circular(TashilRadius.large)
                      : BorderRadiusDirectional.horizontal(
                          start: const Radius.circular(TashilRadius.large),
                        ).resolve(rtl ? TextDirection.rtl : TextDirection.ltr),
                ),
                child: SizedBox(
                  width: width,
                  height: double.infinity,
                  child: Builder(builder: widget.panel),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A body with a standard side sheet at its end edge. Opening the sheet
/// shrinks the body (animated) to make room; both stay usable.
class StandardSideSheetLayout extends StatelessWidget {
  const StandardSideSheetLayout({
    super.key,
    required this.body,
    required this.open,
    required this.title,
    required this.sheet,
    required this.onClose,
    this.actions = const [],
    this.width = 320,
  }) : assert(width <= SideSheetSpec.maxWidth);

  final Widget body;
  final bool open;
  final String title;
  final Widget sheet;
  final VoidCallback onClose;
  final List<Widget> actions;
  final double width;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final d = TashilMotion.scaled(context, TashilMotion.normal.duration);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: body),
        AnimatedContainer(
          duration: d,
          curve: TashilMotion.normal.curve,
          width: open ? width : 0,
          decoration: BoxDecoration(
            color: scheme.surface,
            border: BorderDirectional(
              start: BorderSide(
                color: open ? scheme.outlineVariant : Colors.transparent,
              ),
            ),
          ),
          clipBehavior: Clip.hardEdge,
          child: OverflowBox(
            alignment: AlignmentDirectional.centerStart,
            minWidth: width,
            maxWidth: width,
            child: AnimatedOpacity(
              duration: d,
              opacity: open ? 1 : 0,
              child: ExcludeSemantics(
                excluding: !open,
                child: ExcludeFocus(
                  excluding: !open,
                  child: SideSheetPanel(
                    title: title,
                    onClose: onClose,
                    actions: actions,
                    child: sheet,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
