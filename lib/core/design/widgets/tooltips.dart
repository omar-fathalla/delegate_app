import 'package:material_ui/material_ui.dart';

import '../tokens.dart';

/// Tooltips that follow m3.material.io/components/tooltips/guidelines.
///
/// * **Plain**: Flutter's official [Tooltip] (and the `tooltip:` of
///   [IconButton]). The theme ([plainTooltipTheme]) puts it above the
///   element, 4dp from a 40dp icon button, and keeps it 1.5 s after the
///   pointer leaves or the long press ends. Flutter shows one at a time.
///   Only for elements with no text label; one short line.
/// * **Rich**: [RichTooltip], hand-built because Flutter has no rich
///   tooltip yet (Compose has `RichTooltip`). Optional one-line subhead,
///   supporting text, up to two text buttons side by side. Placed below
///   the element towards its end side (bottom right, bottom left in
///   Arabic), never over it, moved in 8dp steps to stay on screen.
///   * Transient (default): long press or hover, gone 1.5 s after leaving,
///     built on the official [RawTooltip].
///   * Persistent: opens on tap (or from a [RichTooltipController], for
///     explaining a new feature when the page loads) and stays until the
///     person taps somewhere else. Not on icon buttons.
/// * Never put critical information in a tooltip: use a dialog.
abstract final class TashilTooltip {
  /// Gap between the element and a tooltip when the element has a
  /// visible boundary (a button).
  static const gap = 4.0;

  /// Gap from bare text, which has no boundary.
  static const gapFromText = 8.0;

  /// How long a tooltip stays after the pointer leaves or the press ends.
  static const linger = Duration(milliseconds: 1500);

  /// Steps for moving a rich tooltip back on screen.
  static const step = 8.0;

  static const richMaxWidth = 312.0;
}

/// The plain tooltip theme: above the element, 1.5 s linger.
const plainTooltipTheme = TooltipThemeData(
  preferBelow: false,
  // Distance from the element's centre to the tooltip: half a 40dp icon
  // button plus the 4dp gap.
  verticalOffset: 20 + TashilTooltip.gap,
  exitDuration: TashilTooltip.linger,
  showDuration: TashilTooltip.linger,
);

/// For app bars: plain tooltips go below the element there.
final appBarTooltipTheme = plainTooltipTheme.copyWith(preferBelow: true);

/// Where a rich tooltip goes for a [target] rect: below it, starting at
/// its centre and growing towards the end side; moved back in 8dp steps
/// when it would leave the screen, and above the target when there is no
/// room below. Never covers the target.
Offset richTooltipPosition({
  required Rect target,
  required Size tooltip,
  required Size overlay,
  required TextDirection direction,
}) {
  const margin = TashilTooltip.step;
  final ltr = direction == TextDirection.ltr;
  var left = ltr ? target.center.dx : target.center.dx - tooltip.width;
  while (left + tooltip.width > overlay.width - margin && left > margin) {
    left -= TashilTooltip.step;
  }
  while (left < margin && left + tooltip.width < overlay.width - margin) {
    left += TashilTooltip.step;
  }
  var top = target.bottom + TashilTooltip.gap;
  if (top + tooltip.height > overlay.height - margin) {
    top = target.top - TashilTooltip.gap - tooltip.height;
  }
  return Offset(left, top);
}

/// Shows a persistent [RichTooltip] from code, for example to explain a
/// new feature when the page opens.
class RichTooltipController extends ChangeNotifier {
  bool _open = false;
  bool get isOpen => _open;

  void show() {
    if (_open) return;
    Tooltip.dismissAllToolTips();
    _RichTooltipState._current?._close();
    _open = true;
    notifyListeners();
  }

  void hide() {
    if (!_open) return;
    _open = false;
    notifyListeners();
  }
}

class RichTooltip extends StatefulWidget {
  const RichTooltip({
    super.key,
    this.subhead,
    required this.text,
    this.actions = const [],
    this.persistent = false,
    this.controller,
    required this.child,
  });

  /// One line that sums up the message. Include it when the tooltip opens
  /// by itself (page load).
  final String? subhead;
  final String text;

  /// Up to two short [TextButton]s, side by side.
  final List<Widget> actions;

  /// Opens on tap and stays until the person interacts elsewhere.
  final bool persistent;
  final RichTooltipController? controller;
  final Widget child;

  @override
  State<RichTooltip> createState() => _RichTooltipState();
}

class _RichTooltipState extends State<RichTooltip> {
  static _RichTooltipState? _current;

  final _portal = OverlayPortalController();
  late final _ownController = RichTooltipController();
  RichTooltipController get _controller => widget.controller ?? _ownController;
  final _group = Object();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_sync);
    if (_controller.isOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
    }
  }

  @override
  void didUpdateWidget(RichTooltip old) {
    super.didUpdateWidget(old);
    final was = old.controller ?? _ownController;
    if (was != _controller) {
      was.removeListener(_sync);
      _controller.addListener(_sync);
      _sync();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_sync);
    _ownController.dispose();
    if (_current == this) _current = null;
    super.dispose();
  }

  void _sync() {
    if (!mounted) return;
    if (_controller.isOpen) {
      _current = this;
      _portal.show();
    } else {
      if (_current == this) _current = null;
      _portal.hide();
    }
  }

  void _close() => _controller.hide();

  Widget _card(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: TashilTooltip.richMaxWidth),
      child: Material(
        color: scheme.surfaceContainer,
        elevation: 2,
        shadowColor: scheme.shadow,
        borderRadius: BorderRadius.circular(TashilRadius.medium),
        child: Padding(
          padding: EdgeInsetsDirectional.fromSTEB(
            TashilSpacing.lg,
            TashilSpacing.md,
            TashilSpacing.lg,
            widget.actions.isEmpty ? TashilSpacing.md : TashilSpacing.xs,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.subhead != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: TashilSpacing.xs),
                  child: Text(
                    widget.subhead!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              Text(
                widget.text,
                style: text.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (widget.actions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: TashilSpacing.xs),
                  child: Row(
                    children: [
                      for (final a in widget.actions)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(
                            end: TashilSpacing.sm,
                          ),
                          child: a,
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Offset Function(TooltipPositionContext) _position(TextDirection d) =>
      (c) => richTooltipPosition(
        target: Rect.fromCenter(
          center: c.target,
          width: c.targetSize.width,
          height: c.targetSize.height,
        ),
        tooltip: c.tooltipSize,
        overlay: c.overlaySize,
        direction: d,
      );

  @override
  Widget build(BuildContext context) {
    assert(widget.actions.length <= 2, 'M3: at most two text buttons');
    assert(
      widget.controller == null || widget.persistent,
      'Only persistent rich tooltips are opened from code',
    );
    final direction = Directionality.of(context);
    final semantics = [?widget.subhead, widget.text].join('. ');

    if (!widget.persistent) {
      return RawTooltip(
        semanticsTooltip: semantics,
        hoverDelay: const Duration(milliseconds: 300),
        touchDelay: TashilTooltip.linger,
        dismissDelay: TashilTooltip.linger,
        positionDelegate: _position(direction),
        tooltipBuilder: (c, animation) =>
            FadeTransition(opacity: animation, child: _card(c)),
        child: widget.child,
      );
    }

    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _portal,
      overlayChildBuilder: (c, info) {
        final target = MatrixUtils.transformRect(
          info.childPaintTransform,
          Offset.zero & info.childSize,
        );
        return CustomSingleChildLayout(
          delegate: _RichLayout(target, direction),
          child: TapRegion(
            groupId: _group,
            onTapOutside: (_) => _close(),
            child: Semantics(liveRegion: true, child: _card(c)),
          ),
        );
      },
      child: TapRegion(
        groupId: _group,
        child: Semantics(
          tooltip: semantics,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => _controller.isOpen ? _close() : _controller.show(),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class _RichLayout extends SingleChildLayoutDelegate {
  _RichLayout(this.target, this.direction);

  final Rect target;
  final TextDirection direction;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints c) => c.loosen();

  @override
  Offset getPositionForChild(Size size, Size child) => richTooltipPosition(
    target: target,
    tooltip: child,
    overlay: size,
    direction: direction,
  );

  @override
  bool shouldRelayout(_RichLayout old) =>
      old.target != target || old.direction != direction;
}
