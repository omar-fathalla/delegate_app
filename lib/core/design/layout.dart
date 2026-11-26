import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'tokens.dart';

/// Layout that follows m3.material.io/foundations/layout (overview, parts of
/// layout, adaptive design, breakpoints).
///
/// * **Breakpoints** (previously window size classes): five widths at which
///   the layout changes. Design for breakpoints, not devices: the window
///   changes with rotation, split screen and resizing.
/// * **Layout scaffold**: bars frame the page, rails hold navigation and
///   primary controls, and all content sits in 1 to 3 **panes**.
/// * **Adaptive strategies**: reveal, divide, resize, reposition, swap.
///   Swap only components that do the same job (bar and rail, FAB and
///   extended FAB), never a button for a chip or a menu.
/// * RTL: the first pane and the navigation are on the right in Arabic,
///   because everything here uses the reading direction.
enum TashilBreakpoint {
  /// Under 600dp: phone in portrait, SUNMI V3 (360dp).
  compact(0),

  /// 600 to 839dp: tablet or unfolded foldable in portrait.
  medium(600),

  /// 840 to 1199dp: tablet or phone in landscape, small desktop window.
  expanded(840),

  /// 1200 to 1599dp: desktop, the admin panel.
  large(1200),

  /// 1600dp and wider: desktop, ultra-wide monitors.
  extraLarge(1600);

  const TashilBreakpoint(this.minWidth);

  /// Smallest window width (dp) in this breakpoint.
  final double minWidth;

  static TashilBreakpoint fromWidth(double width) {
    for (final b in values.reversed) {
      if (width >= b.minWidth) return b;
    }
    return compact;
  }

  /// The breakpoint of the window.
  static TashilBreakpoint of(BuildContext context) =>
      fromWidth(MediaQuery.sizeOf(context).width);

  bool operator >=(TashilBreakpoint other) => index >= other.index;
  bool operator <(TashilBreakpoint other) => index < other.index;

  /// Leading and trailing margin: 16dp on compact, 24dp from medium.
  double get margin => this == compact ? 16 : 24;

  /// Space between two panes: 24dp at every breakpoint that has two.
  double get spacer => 24;

  /// Highest number of panes M3 allows here (never more than three).
  int get maxPanes => switch (this) {
    compact => 1,
    medium || expanded || large => 2,
    extraLarge => 3,
  };

  /// Panes M3 recommends: one up to medium (two only for low-density
  /// content like settings), two from expanded, up to three on extra-large.
  int get recommendedPanes => switch (this) {
    compact || medium => 1,
    expanded || large => 2,
    extraLarge => 3,
  };

  /// Default width of the fixed pane in a fixed-and-flexible layout:
  /// 360dp on expanded, 412dp on large and extra-large. Medium splits 50/50.
  double? get fixedPaneWidth => switch (this) {
    compact || medium => null,
    expanded => 360,
    large || extraLarge => 412,
  };

  /// Full-screen dialogs only on compact; from medium a basic dialog does
  /// the same job (M3 breakpoints > common swappable components).
  bool get allowsFullScreenDialog => this == compact;

  /// Supplemental selection (sort, pick an option) is a bottom sheet on
  /// compact and a menu from medium.
  SupplementalSelection get supplementalSelection => this == compact
      ? SupplementalSelection.bottomSheet
      : SupplementalSelection.menu;

  /// Whether a two-pane layout here should pair with a navigation bar
  /// instead of a rail: on medium the two panes need the full width.
  bool navigationBarWithTwoPanes(int panes) => this == medium && panes == 2;

  /// Layout grid columns (m3.material.io/foundations/layout/grids-spacing):
  /// 4 on compact (phone), 8 on medium and expanded (foldable, tablet).
  /// 12 from large is our choice for desktop; M3 only shows 4 and 8.
  int get columns => switch (this) {
    compact => 4,
    medium || expanded => 8,
    large || extraLarge => 12,
  };

  /// Space between grid columns: same as the margin (16 compact, 24 from
  /// medium), so the edges and the gutters share one rhythm.
  double get gutter => margin;

  /// Arabic name for the playground and debug labels.
  String get label => switch (this) {
    compact => 'مضغوط',
    medium => 'متوسط',
    expanded => 'موسّع',
    large => 'كبير',
    extraLarge => 'كبير جداً',
  };
}

/// The component for a supplemental selection at a breakpoint.
enum SupplementalSelection { bottomSheet, menu }

/// Height breakpoints (Android window size classes for height): compact
/// under 480dp, medium 480 to 899dp, expanded from 900dp. Most layouts
/// scroll vertically and never need them; use them only when vertical
/// space is unusually small, such as a phone in landscape with the
/// keyboard open at the counter.
enum TashilHeightBreakpoint {
  compact(0),
  medium(480),
  expanded(900);

  const TashilHeightBreakpoint(this.minHeight);

  final double minHeight;

  static TashilHeightBreakpoint fromHeight(double height) => height >= 900
      ? expanded
      : height >= 480
      ? medium
      : compact;

  static TashilHeightBreakpoint of(BuildContext context) =>
      fromHeight(MediaQuery.sizeOf(context).height);
}

/// How a two-pane layout shares the width (M3 scaffold > panes). Every
/// layout keeps at least one flexible pane.
enum PaneSplit {
  /// First pane fixed ([TashilBreakpoint.fixedPaneWidth]), second flexible.
  /// List-detail: invoices + the open invoice.
  fixedFlexible,

  /// First pane flexible, second fixed: a supporting pane at the end
  /// (filters, cart summary). Fixed panes are often temporary.
  flexibleFixed,

  /// Both panes flexible, spacer visually centred in the window, also when
  /// a navigation rail takes space from the first pane ([NavigationInset]).
  split,
}

/// Which pane is left after collapsing with the drag handle.
enum PaneCollapse { none, firstOnly, secondOnly }

/// Whether a resized pane width is remembered (M3 "persistent pane
/// resizing", the default for most layouts) or goes back to the default
/// when the pane closes (temporary, for supporting panes).
enum PaneResizing { persistent, temporary }

/// Holds the width the person chose with the drag handle and whether a
/// pane is collapsed. Keep one per screen (and save [sizedWidth] and
/// [collapse] with the user's settings) so the choice survives breakpoint
/// changes and app restarts: a layout collapsed to one pane stays one pane
/// on every breakpoint until the person brings the other pane back.
class PaneLayoutController extends ChangeNotifier {
  PaneLayoutController({
    double? sizedWidth,
    PaneCollapse collapse = PaneCollapse.none,
  }) : _sizedWidth = sizedWidth,
       _collapse = collapse;

  double? _sizedWidth;
  PaneCollapse _collapse;

  /// Width of the fixed pane (the first pane in a split layout), or null
  /// for the breakpoint default.
  double? get sizedWidth => _sizedWidth;
  PaneCollapse get collapse => _collapse;

  void resize(double? width) {
    if (_sizedWidth == width && _collapse == PaneCollapse.none) return;
    _sizedWidth = width;
    _collapse = PaneCollapse.none;
    notifyListeners();
  }

  void collapseTo(PaneCollapse c) {
    if (_collapse == c) return;
    _collapse = c;
    notifyListeners();
  }

  /// Back to the default layout.
  void reset() {
    _sizedWidth = null;
    _collapse = PaneCollapse.none;
    notifyListeners();
  }
}

/// Width of the navigation rail next to a [PaneLayout], so a split layout
/// keeps its spacer centred in the window. [AdaptiveNavigationScaffold]
/// provides it.
class NavigationInset extends InheritedWidget {
  const NavigationInset({super.key, required this.width, required super.child});

  final double width;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NavigationInset>()?.width ?? 0;

  @override
  bool updateShouldNotify(NavigationInset old) => old.width != width;
}

/// The panes of the layout scaffold: 1 to 3 panes with the breakpoint's
/// margins and 24dp spacers, a drag handle between the first two, and the
/// M3 adaptive strategies (show and hide, reflow).
///
/// Flutter has no pane scaffold (Compose has `ListDetailPaneScaffold`,
/// and the `flutter_adaptive_scaffold` package is discontinued), so this
/// one is ours.
///
/// * One pane fits (compact, and medium unless [twoPanesOnMedium]):
///   **show and hide** shows [second] when [showSecond] is true (an item is
///   open), else [first]; the caller handles back. With [reflow] the panes
///   **stack** instead, the second under the first (a supporting pane).
/// * Two panes: co-planar, side by side, in reading order (focus order
///   follows it). With no [second] the first pane takes the whole width, or
///   [placeholder] fills the space ("pick an invoice").
/// * [third] (extra-large only): a standard side sheet as a third pane, max
///   400dp. Never more than three panes.
/// * The drag handle resizes, snaps to 360 / 412dp (and the centre in a
///   split layout) when released near them, collapses a pane when dragged
///   to an edge, and a tap toggles between one and two panes.
class PaneLayout extends StatefulWidget {
  const PaneLayout({
    super.key,
    required this.first,
    this.second,
    this.third,
    this.placeholder,
    this.showSecond = false,
    this.split = PaneSplit.fixedFlexible,
    this.twoPanesOnMedium = false,
    this.reflow = false,
    this.resizable = true,
    this.resizing = PaneResizing.persistent,
    this.controller,
    this.contained = false,
    this.breakpoint,
  });

  final Widget first;
  final Widget? second;
  final Widget? third;

  /// Fills the second pane when there is room for it but no [second].
  final Widget? placeholder;

  /// On one-pane breakpoints: show [second] instead of [first].
  final bool showSecond;
  final PaneSplit split;

  /// Medium allows two 50/50 panes for low-density content (settings).
  final bool twoPanesOnMedium;

  /// On one-pane breakpoints stack [second] under [first] instead of
  /// showing one of them.
  final bool reflow;

  /// Shows the drag handle between the first two panes.
  final bool resizable;
  final PaneResizing resizing;

  /// Keeps the chosen width; one is made if null. With
  /// [PaneResizing.temporary] the layout resets it when [second] closes.
  final PaneLayoutController? controller;

  /// Explicit grouping: panes get a container colour and rounded corners.
  /// Off (implicit grouping) the panes blend with the background.
  final bool contained;

  /// Override for previews; defaults to the width this widget gets.
  final TashilBreakpoint? breakpoint;

  /// Widths the drag handle snaps to (M3 recommended custom widths).
  static const snapWidths = [360.0, 412.0];

  /// How close (dp) a released handle must be to snap.
  static const snapDistance = 32.0;

  @override
  State<PaneLayout> createState() => _PaneLayoutState();
}

class _PaneLayoutState extends State<PaneLayout> {
  PaneLayoutController? _own;
  PaneLayoutController get _c =>
      widget.controller ?? (_own ??= PaneLayoutController());

  /// Width while dragging; snapped and stored on release.
  double? _dragFirst;

  static const _minPane = 240.0;
  static const _thirdWidth = 400.0;
  static const _keyStep = 24.0;

  @override
  void initState() {
    super.initState();
    _c.addListener(_changed);
  }

  @override
  void didUpdateWidget(PaneLayout old) {
    super.didUpdateWidget(old);
    final was = old.controller ?? _own;
    if (was != _c) {
      was?.removeListener(_changed);
      _c.addListener(_changed);
    }
    // Temporary resizing: back to the default once the pane closes.
    if (widget.resizing == PaneResizing.temporary &&
        old.second != null &&
        widget.second == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _c.reset());
    }
  }

  @override
  void dispose() {
    _c.removeListener(_changed);
    _own?.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  int _panes(TashilBreakpoint b) {
    final w = widget;
    if (b == TashilBreakpoint.compact) return 1;
    if (b == TashilBreakpoint.medium && !w.twoPanesOnMedium) return 1;
    if (w.second == null && w.placeholder == null) return 1;
    if (b == TashilBreakpoint.extraLarge && w.third != null) return 3;
    return 2;
  }

  Widget _pane(Widget child) {
    if (!widget.contained) return child;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(TashilRadius.large),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final nav = NavigationInset.of(context);
    return LayoutBuilder(
      builder: (context, c) {
        final w = widget;
        final b = w.breakpoint ?? TashilBreakpoint.fromWidth(c.maxWidth + nav);
        final panes = _panes(b);
        final margin = EdgeInsets.symmetric(horizontal: b.margin);
        final secondPane = w.second ?? w.placeholder;

        if (panes == 1) {
          if (w.reflow && w.second != null) {
            return Padding(
              padding: margin,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 3, child: _pane(w.first)),
                  SizedBox(height: b.spacer),
                  Expanded(flex: 2, child: _pane(w.second!)),
                ],
              ),
            );
          }
          final showSecond = w.showSecond && w.second != null;
          return Padding(
            padding: margin,
            child: _pane(
              KeyedSubtree(
                key: ValueKey(showSecond),
                child: showSecond ? w.second! : w.first,
              ),
            ),
          );
        }

        // Collapsed with the drag handle: one pane, the handle stays at its
        // edge so the person can bring the other pane back.
        if (_c.collapse != PaneCollapse.none) {
          final onlyFirst = _c.collapse == PaneCollapse.firstOnly;
          final handle = SizedBox(
            width: b.spacer,
            child: PaneDragHandle(
              expanded: false,
              onDrag: (d) {
                if (onlyFirst ? d < 0 : d > 0) _c.reset();
              },
              onToggle: _c.reset,
              onReset: _c.reset,
            ),
          );
          final pane = Expanded(
            child: _pane(onlyFirst ? w.first : secondPane!),
          );
          return Padding(
            padding: margin,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: onlyFirst ? [pane, handle] : [handle, pane],
            ),
          );
        }

        final third = panes == 3 ? w.third : null;
        final inner =
            c.maxWidth -
            2 * b.margin -
            b.spacer -
            (third == null ? 0 : _thirdWidth + b.spacer);
        final maxFirst = (inner - _minPane).clamp(_minPane, double.infinity);
        final fixed = b.fixedPaneWidth ?? inner / 2;
        // Split: navigation and first pane together take half the window,
        // so the spacer sits in the middle of the window.
        final centred = (c.maxWidth + nav) / 2 - nav - b.margin - b.spacer / 2;

        double firstFromSized(double sized) =>
            w.split == PaneSplit.flexibleFixed ? inner - sized : sized;
        double sizedFromFirst(double first) =>
            w.split == PaneSplit.flexibleFixed ? inner - first : first;

        final defaultFirst = switch (w.split) {
          PaneSplit.fixedFlexible => fixed,
          PaneSplit.flexibleFixed => inner - fixed,
          PaneSplit.split => centred,
        };
        final stored = _c.sizedWidth;
        final first =
            (_dragFirst ??
                    (stored == null ? defaultFirst : firstFromSized(stored)))
                .clamp(_minPane, maxFirst);

        void drag(double delta) {
          final next = first + delta;
          if (next < _minPane - 48) {
            _dragFirst = null;
            _c.collapseTo(PaneCollapse.secondOnly);
          } else if (next > maxFirst + 48) {
            _dragFirst = null;
            _c.collapseTo(PaneCollapse.firstOnly);
          } else {
            setState(() => _dragFirst = next.clamp(_minPane, maxFirst));
          }
        }

        void release() {
          final f = _dragFirst;
          if (f == null) return;
          var sized = sizedFromFirst(f);
          final targets = [
            ...PaneLayout.snapWidths,
            if (w.split == PaneSplit.split) centred,
          ];
          for (final t in targets) {
            if ((sized - t).abs() <= PaneLayout.snapDistance) sized = t;
          }
          _dragFirst = null;
          _c.resize(sized);
        }

        void toggle() => _c.collapseTo(
          w.split == PaneSplit.flexibleFixed
              ? PaneCollapse.firstOnly
              : PaneCollapse.secondOnly,
        );

        return Padding(
          padding: margin,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: first, child: _pane(w.first)),
              SizedBox(
                width: b.spacer,
                child: w.resizable
                    ? PaneDragHandle(
                        onDrag: drag,
                        onDragEnd: release,
                        step: _keyStep,
                        onToggle: toggle,
                        onReset: _c.reset,
                      )
                    : null,
              ),
              Expanded(child: _pane(secondPane!)),
              if (third != null) ...[
                SizedBox(width: b.spacer),
                SizedBox(width: _thirdWidth, child: _pane(third)),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// The drag handle that resizes panes (M3 "Drag handle"): a 4 x 48dp pill
/// in the spacer, 24dp wide hit area, resize cursor on hover. Drags follow
/// the reading direction (in Arabic, dragging left grows the first pane).
/// A tap (or Enter / Space) toggles between one and two panes, arrow keys
/// resize, Home resets, and screen readers get increase, decrease and tap.
class PaneDragHandle extends StatefulWidget {
  const PaneDragHandle({
    super.key,
    required this.onDrag,
    this.onDragEnd,
    this.onToggle,
    this.onReset,
    this.step = 24,
    this.expanded = true,
  });

  /// Change in the first pane's width, in dp, positive = wider.
  final ValueChanged<double> onDrag;

  /// Released: the layout snaps to the nearest recommended width.
  final VoidCallback? onDragEnd;

  /// Switch between the one-pane and two-pane layout.
  final VoidCallback? onToggle;
  final VoidCallback? onReset;
  final double step;

  /// True while both panes show.
  final bool expanded;

  @override
  State<PaneDragHandle> createState() => _PaneDragHandleState();
}

class _PaneDragHandleState extends State<PaneDragHandle> {
  bool _hover = false;
  bool _dragging = false;
  bool _focused = false;

  void _grow(double by) {
    widget.onDrag(by);
    widget.onDragEnd?.call();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final active = _dragging || _hover || _focused;
    double sign(double dx) => rtl ? -dx : dx;
    return Semantics(
      label: 'تغيير عرض الأجزاء',
      hint: widget.expanded ? 'اضغط للعرض بجزء واحد' : 'اضغط لإظهار الجزأين',
      onIncrease: () => _grow(widget.step),
      onDecrease: () => _grow(-widget.step),
      onTap: widget.onToggle,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.resizeColumn,
        onShowHoverHighlight: (v) => setState(() => _hover = v),
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        shortcuts: {
          SingleActivator(
            rtl ? LogicalKeyboardKey.arrowLeft : LogicalKeyboardKey.arrowRight,
          ): const _GrowIntent(
            1,
          ),
          SingleActivator(
            rtl ? LogicalKeyboardKey.arrowRight : LogicalKeyboardKey.arrowLeft,
          ): const _GrowIntent(
            -1,
          ),
          const SingleActivator(LogicalKeyboardKey.home): const _ResetIntent(),
          const SingleActivator(LogicalKeyboardKey.enter):
              const ActivateIntent(),
          const SingleActivator(LogicalKeyboardKey.space):
              const ActivateIntent(),
        },
        actions: {
          _GrowIntent: CallbackAction<_GrowIntent>(
            onInvoke: (i) => _grow(i.sign * widget.step),
          ),
          _ResetIntent: CallbackAction<_ResetIntent>(
            onInvoke: (_) => widget.onReset?.call(),
          ),
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) => widget.onToggle?.call(),
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onToggle,
          onHorizontalDragStart: (_) => setState(() => _dragging = true),
          onHorizontalDragUpdate: (d) => widget.onDrag(sign(d.delta.dx)),
          onHorizontalDragEnd: (_) {
            setState(() => _dragging = false);
            widget.onDragEnd?.call();
          },
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: active ? 12 : 4,
              height: _dragging ? 52 : 48,
              decoration: BoxDecoration(
                color: _dragging ? scheme.onSurface : scheme.outline,
                borderRadius: BorderRadius.circular(TashilRadius.full),
                border: _focused
                    ? Border.all(color: scheme.secondary, width: 2)
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GrowIntent extends Intent {
  const _GrowIntent(this.sign);
  final int sign;
}

class _ResetIntent extends Intent {
  const _ResetIntent();
}

/// Keeps long text at a readable line length (M3: 40 to 60 characters per
/// line at every breakpoint) and at the start edge.
class ReadingWidth extends StatelessWidget {
  const ReadingWidth({super.key, required this.child, this.characters = 60});

  final Widget child;
  final int characters;

  /// About half an em per character for Cairo body text.
  static double maxWidthFor(BuildContext context, {int characters = 60}) {
    final size =
        Theme.of(context).textTheme.bodyLarge?.fontSize ?? 16; // dp, unscaled
    final scaled = MediaQuery.textScalerOf(context).scale(size);
    return characters * scaled * 0.55;
  }

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.topStart,
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: maxWidthFor(context, characters: characters),
      ),
      child: child,
    ),
  );
}

/// A FAB that changes presentation with the window (M3 adaptive
/// components): standard FAB on compact and medium, extended FAB with its
/// label from expanded. Same action either way.
class AdaptiveFab extends StatelessWidget {
  const AdaptiveFab({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.breakpoint,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final TashilBreakpoint? breakpoint;

  @override
  Widget build(BuildContext context) {
    final b = breakpoint ?? TashilBreakpoint.of(context);
    if (b >= TashilBreakpoint.expanded) {
      return FloatingActionButton.extended(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
      );
    }
    return FloatingActionButton(
      onPressed: onPressed,
      tooltip: label,
      child: Icon(icon),
    );
  }
}

/// Column grid of one pane or window (M3 grids and spacing). The grid is
/// for aligning content, not a cage: bars and rails sit outside it (they
/// are placed first, nearest the screen edges), panes and their content
/// line up on its columns.
@immutable
class ColumnGrid {
  const ColumnGrid({
    required this.width,
    required this.columns,
    required this.gutter,
    required this.margin,
  }) : assert(columns > 0);

  /// The grid of [breakpoint] across a [width] that still includes margins.
  factory ColumnGrid.of(double width, TashilBreakpoint breakpoint) =>
      ColumnGrid(
        width: width,
        columns: breakpoint.columns,
        gutter: breakpoint.gutter,
        margin: breakpoint.margin,
      );

  final double width;
  final int columns;
  final double gutter;
  final double margin;

  /// Width of one column.
  double get column =>
      math.max(0, (width - 2 * margin - (columns - 1) * gutter) / columns);

  /// Width of [n] columns with the gutters between them. Use it to size
  /// cards and fields so their edges fall on the grid.
  double span(int n) {
    final c = n.clamp(1, columns);
    return c * column + (c - 1) * gutter;
  }

  /// Distance from the leading edge to the start of column [i] (0-based):
  /// the "content ruler" that titles and leading icons line up on.
  double start(int i) => margin + i.clamp(0, columns - 1) * (column + gutter);
}

/// Debug overlay that tints the columns of the grid, for the playground
/// and for checking alignment. Ignores pointers.
class ColumnGridOverlay extends StatelessWidget {
  const ColumnGridOverlay({super.key, this.breakpoint});

  final TashilBreakpoint? breakpoint;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.error.withValues(alpha: 0.08);
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, c) {
          final b = breakpoint ?? TashilBreakpoint.fromWidth(c.maxWidth);
          final grid = ColumnGrid.of(c.maxWidth, b);
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: grid.margin),
            child: Row(
              spacing: grid.gutter,
              children: [
                for (var i = 0; i < grid.columns; i++)
                  Expanded(child: ColoredBox(color: color)),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// M3 density scale (m3.material.io/foundations/layout/grids-spacing/density).
/// Each step down removes 4dp of top and bottom padding (or height). Text
/// size never changes.
///
/// * Opt-in only: the person picks it in settings. Never switch density
///   because of breakpoint or orientation.
/// * Only for information-dense screens: lists, tables, long forms
///   (inventory, reports). Not for focused tasks or alerts: menus,
///   dialogs, snackbars keep the default.
/// * Touch targets stay 48dp even when the visual gets smaller.
enum TashilDensity {
  standard(0),
  comfortable(-1),
  compact(-2),
  dense(-3);

  const TashilDensity(this.step);

  /// 0, -1, -2 or -3; each step is 4dp.
  final int step;

  /// Flutter's density uses the same 4dp steps, vertical only.
  VisualDensity get visualDensity =>
      VisualDensity(horizontal: 0, vertical: step.toDouble());

  String get label => switch (this) {
    standard => 'عادي',
    comfortable => '-1',
    compact => '-2',
    dense => '-3',
  };
}

/// Applies a [TashilDensity] to a dense part of a screen (a list, a table,
/// a long form): list rows, text fields and data table rows get shorter.
///
/// Buttons, checkboxes, switches and icon buttons keep standard density:
/// Flutter shrinks their touch target with density, and M3 keeps targets
/// at 48dp. List and table rows never go below 48dp either.
///
/// Dialogs, menus and sheets opened from inside capture this theme, so
/// open them from outside the scope or wrap their content in
/// `DensityScope(density: TashilDensity.standard)`: M3 never densifies
/// focused tasks and alerts.
class DensityScope extends StatelessWidget {
  const DensityScope({super.key, required this.density, required this.child});

  final TashilDensity density;
  final Widget child;

  /// M3 data table row (52dp) and header (56dp) heights at [density].
  static double dataRowHeight(TashilDensity density) =>
      math.max(TashilSizes.minTouch, 52.0 + 4 * density.step);
  static double headingRowHeight(TashilDensity density) =>
      math.max(TashilSizes.minTouch, 56.0 + 4 * density.step);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final v = density.visualDensity;
    return Theme(
      data: theme.copyWith(
        // One-line rows are 56dp: -2 already reaches 48, so stop there.
        listTileTheme: theme.listTileTheme.copyWith(
          visualDensity: VisualDensity(
            vertical: math.max(-2, density.step).toDouble(),
          ),
        ),
        inputDecorationTheme: theme.inputDecorationTheme.copyWith(
          visualDensity: v,
        ),
        dataTableTheme: theme.dataTableTheme.copyWith(
          dataRowMinHeight: dataRowHeight(density),
          dataRowMaxHeight: dataRowHeight(density),
          headingRowHeight: headingRowHeight(density),
        ),
      ),
      child: child,
    );
  }
}
