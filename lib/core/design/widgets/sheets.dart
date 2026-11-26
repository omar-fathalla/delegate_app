import 'package:material_ui/material_ui.dart';

import '../motion.dart';
import '../tokens.dart';
import 'side_sheets.dart';

export 'side_sheets.dart';

/// Bottom sheets that follow m3.material.io/components/bottom-sheets,
/// built on Flutter's official [showModalBottomSheet],
/// [DraggableScrollableSheet] and [DraggableScrollableController].
///
/// Rules (docs/design-system.md, "Bottom sheets"):
/// * **Modal** (mobile only): actions on an item, instead of a menu when
///   the list is long or items need icons and descriptions. Opens at its
///   content height, never above 50% of the screen; longer content can be
///   pulled to full screen and scrolls inside. At full screen it shows a
///   close button. Closes by choosing an action, tapping the scrim,
///   swiping down, the close button, or back (predictive back from
///   Flutter's route).
/// * **Standard**: lives next to the main UI, both usable at once (the
///   cart over the product grid). Preset heights; at full height a
///   collapse button returns it to the first preset.
/// * **Drag handle**: drag it, or tap it to move to the next preset
///   height (the single-pointer alternative M3 requires).
/// * **Larger screens**: max width 640dp (Flutter's default). From 840dp
///   the same content opens as a side sheet ([showAdaptiveSheet]).
class SheetAction<T> {
  const SheetAction({
    required this.label,
    required this.value,
    this.icon,
    this.supportingText,
    this.enabled = true,
  });

  final String label;
  final T value;
  final IconData? icon;
  final String? supportingText;
  final bool enabled;
}

/// Heights used to work out where a modal sheet opens.
abstract final class _SheetMetrics {
  static const handle = 48.0;
  static const title = 48.0;
  static const item = 56.0;
  static const itemWithSupporting = 72.0;
  static const divider = 17.0;
  static const bottom = TashilSpacing.lg;
}

/// A modal bottom sheet of actions, grouped with dividers between
/// groups. Returns the chosen action's value, or null when dismissed.
Future<T?> showActionSheet<T>({
  required BuildContext context,
  String? title,
  required List<List<SheetAction<T>>> groups,
}) {
  final screen = MediaQuery.sizeOf(context).height;
  final content =
      _SheetMetrics.handle +
      (title == null ? 0 : _SheetMetrics.title) +
      [
        for (final g in groups)
          for (final a in g)
            a.supportingText == null
                ? _SheetMetrics.item
                : _SheetMetrics.itemWithSupporting,
      ].fold(0.0, (a, b) => a + b) +
      (groups.length - 1) * _SheetMetrics.divider +
      _SheetMetrics.bottom +
      MediaQuery.paddingOf(context).bottom;

  // M3: the first position never goes above half the screen. Longer
  // content can be pulled up to full screen.
  final initial = (content / screen).clamp(0.1, 0.5);
  final long = content / screen > 0.5;

  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    clipBehavior: Clip.antiAlias,
    builder: (sheetContext) => _ModalSheet(
      initial: initial,
      long: long,
      builder: (c, scroll, controller) => SheetFrame(
        scrollController: scroll,
        controller: controller,
        presets: long ? [initial, 1] : [initial],
        title: title,
        onClose: () => Navigator.pop(sheetContext),
        closeIcon: Icons.close,
        children: [
          for (final (i, g) in groups.indexed) ...[
            if (i > 0) const Divider(),
            for (final a in g)
              ListTile(
                enabled: a.enabled,
                leading: a.icon == null ? null : Icon(a.icon),
                title: Text(a.label),
                subtitle: a.supportingText == null
                    ? null
                    : Text(a.supportingText!),
                onTap: () => Navigator.pop(sheetContext, a.value),
              ),
          ],
          const SizedBox(height: _SheetMetrics.bottom),
        ],
      ),
    ),
  );
}

class _ModalSheet extends StatefulWidget {
  const _ModalSheet({
    required this.initial,
    required this.long,
    required this.builder,
  });

  final double initial;
  final bool long;
  final Widget Function(
    BuildContext,
    ScrollController,
    DraggableScrollableController,
  )
  builder;

  @override
  State<_ModalSheet> createState() => _ModalSheetState();
}

class _ModalSheetState extends State<_ModalSheet> {
  final _controller = DraggableScrollableController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
    controller: _controller,
    expand: false,
    initialChildSize: widget.initial,
    minChildSize: 0,
    maxChildSize: widget.long ? 1 : widget.initial,
    snap: true,
    snapSizes: [widget.initial],
    builder: (c, scroll) => widget.builder(c, scroll, _controller),
  );
}

/// Bottom sheet on compact and medium windows, side sheet from 840dp
/// (M3: on larger screens a side sheet can show the same content).
Future<T?> showAdaptiveSheet<T>({
  required BuildContext context,
  required String title,
  required WidgetBuilder builder,
}) {
  if (MediaQuery.sizeOf(context).width >= TashilSizes.mediumMax) {
    return showSideSheet<T>(context: context, title: title, builder: builder);
  }
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    builder: (c) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: TashilSpacing.lg),
          child: Text(title, style: Theme.of(c).textTheme.titleLarge),
        ),
        builder(c),
        const SizedBox(height: TashilSpacing.lg),
      ],
    ),
  );
}

/// A standard (non-modal) bottom sheet that sits over the bottom of the
/// screen while the content above stays usable. Put it last in a [Stack].
class StandardBottomSheet extends StatefulWidget {
  const StandardBottomSheet({
    super.key,
    required this.presets,
    required this.children,
    this.title,
  }) : assert(presets.length >= 1);

  /// Heights as fractions of the available height, smallest first (e.g.
  /// peek, half, full).
  final List<double> presets;
  final String? title;
  final List<Widget> children;

  @override
  State<StandardBottomSheet> createState() => _StandardBottomSheetState();
}

class _StandardBottomSheetState extends State<StandardBottomSheet> {
  final _controller = DraggableScrollableController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.presets;
    return DraggableScrollableSheet(
      controller: _controller,
      initialChildSize: p.first,
      minChildSize: p.first,
      maxChildSize: p.last,
      snap: true,
      snapSizes: p.length > 2 ? p.sublist(1, p.length - 1) : null,
      builder: (c, scroll) => Material(
        color: Theme.of(c).colorScheme.surfaceContainerLow,
        elevation: 1,
        shadowColor: Theme.of(c).colorScheme.shadow,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(TashilRadius.extraLarge),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: SheetFrame(
          scrollController: scroll,
          controller: _controller,
          presets: p,
          title: widget.title,
          closeIcon: Icons.expand_more,
          onClose: () => _controller.animateTo(
            p.first,
            duration: TashilMotion.scaled(c, TashilMotion.normal.duration),
            curve: TashilMotion.normal.curve,
          ),
          children: widget.children,
        ),
      ),
    );
  }
}

/// The inside of a sheet: a drag handle (tap it to go to the next preset
/// height), an optional title, and the scrolling content. At full screen
/// the handle becomes an app bar with [closeIcon] ("close" for a modal,
/// "collapse" for a standard sheet).
class SheetFrame extends StatefulWidget {
  const SheetFrame({
    super.key,
    required this.scrollController,
    required this.presets,
    required this.children,
    required this.onClose,
    required this.closeIcon,
    required this.controller,
    this.title,
  });

  final ScrollController scrollController;

  final DraggableScrollableController controller;
  final List<double> presets;
  final String? title;
  final List<Widget> children;
  final VoidCallback onClose;
  final IconData closeIcon;

  @override
  State<SheetFrame> createState() => _SheetFrameState();
}

class _SheetFrameState extends State<SheetFrame> {
  late double _extent = widget.presets.first;

  bool get _full => widget.presets.last >= 1 && _extent >= 0.99;

  void _next(BuildContext context) {
    final p = widget.presets;
    if (p.length < 2) return;
    final c = widget.controller;
    // Next preset up; from the top one, back to the first.
    final i = p.indexWhere((h) => h > _extent + 0.01);
    final target = i == -1 ? p.first : p[i];
    final d = TashilMotion.scaled(context, TashilMotion.normal.duration);
    if (c.isAttached) {
      c.animateTo(target, duration: d, curve: TashilMotion.normal.curve);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l = MaterialLocalizations.of(context);
    final canCycle = widget.presets.length > 1;

    final handle = Semantics(
      button: canCycle,
      label: canCycle ? 'تغيير ارتفاع الورقة' : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: canCycle ? () => _next(context) : null,
        child: SizedBox(
          height: _SheetMetrics.handle,
          child: Center(
            child: Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.onSurfaceVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );

    final header = _full
        ? Padding(
            padding: const EdgeInsets.symmetric(vertical: TashilSpacing.xs),
            child: Row(
              children: [
                IconButton(
                  tooltip: widget.closeIcon == Icons.close
                      ? l.closeButtonTooltip
                      : 'تصغير',
                  icon: Icon(widget.closeIcon),
                  onPressed: widget.onClose,
                ),
                if (widget.title != null)
                  Expanded(
                    child: Text(
                      widget.title!,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
              ],
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              handle,
              if (widget.title != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: TashilSpacing.lg,
                  ),
                  child: SizedBox(
                    height: _SheetMetrics.title,
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        widget.title!,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ),
                ),
            ],
          );

    return NotificationListener<DraggableScrollableNotification>(
      onNotification: (n) {
        if ((n.extent - _extent).abs() > 0.005) {
          setState(() => _extent = n.extent);
        }
        return false;
      },
      child: CustomScrollView(
        controller: widget.scrollController,
        slivers: [
          PinnedHeaderSliver(
            child: ColoredBox(color: scheme.surfaceContainerLow, child: header),
          ),
          SliverList.list(children: widget.children),
        ],
      ),
    );
  }
}
