import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

import '../layout.dart';
import '../motion.dart';
import '../tokens.dart';
import 'toolbar.dart';

/// Navigation that follows the M3 Expressive pages
/// (m3.material.io/components/navigation-bar, navigation-rail,
/// navigation-drawer). Built only from Flutter's official
/// [NavigationBar], [NavigationRail], [Drawer] and [Badge].
///
/// Rules (docs/design-system.md, "Navigation"):
/// * Compact (< 600dp, SUNMI V3): navigation bar, 3 to 5 destinations,
///   labels always shown, 64dp tall (flexible bar). It hides while the
///   content scrolls down and comes back on scroll up.
/// * Medium and up: navigation rail instead of the bar, never both. The
///   rail is collapsed (96dp, labels under the icons) with a menu button
///   that expands it to show every destination.
/// * The navigation drawer is no longer recommended: secondary
///   destinations live in the expanded rail. On compact the expanded rail
///   opens as a modal over the content (☰ in the app bar).
class TashilDestination {
  const TashilDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.badge,
  });

  final IconData icon;

  /// Filled version, shown when selected.
  final IconData selectedIcon;
  final String label;

  /// null: no badge; 0: small dot; above 0: the count (999+ max).
  final int? badge;

  Widget iconWidget({bool selected = false}) {
    final child = Icon(selected ? selectedIcon : icon);
    return switch (badge) {
      null => child,
      0 => Badge(child: child),
      final n => Badge.count(count: n, maxCount: 999, child: child),
    };
  }
}

/// Navigation bar that hides while the content scrolls down (M3 behaviour,
/// "Scrolling"). Put [HideOnScroll.listener] around the scrolling body.
/// It never hides while a screen reader is on.
class HidingNavigationBar extends StatelessWidget {
  const HidingNavigationBar({
    super.key,
    required this.visible,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final ValueListenable<bool> visible;
  final List<TashilDestination> destinations;
  final int? selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  /// M3 Expressive flexible navigation bar height.
  static const height = 64.0;

  @override
  Widget build(BuildContext context) {
    final a11y = MediaQuery.maybeAccessibleNavigationOf(context) ?? false;
    final duration = TashilMotion.scaled(
      context,
      TashilEasing.emphasizedDecelerate.duration,
    );
    return ValueListenableBuilder<bool>(
      valueListenable: visible,
      builder: (context, show, child) {
        final shown = show || a11y;
        return ClipRect(
          child: AnimatedAlign(
            alignment: Alignment.topCenter,
            heightFactor: shown ? 1 : 0,
            duration: duration,
            curve: shown
                ? TashilEasing.emphasizedDecelerate.curve
                : TashilEasing.emphasizedAccelerate.curve,
            child: child,
          ),
        );
      },
      // Flutter's bar always selects one item. When the current screen is
      // not in the bar (a secondary destination), nothing looks selected.
      child: NavigationBar(
        height: height,
        selectedIndex: selectedIndex ?? 0,
        indicatorColor: selectedIndex == null ? Colors.transparent : null,
        onDestinationSelected: onDestinationSelected,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          for (final d in destinations)
            NavigationDestination(
              icon: d.iconWidget(),
              selectedIcon: d.iconWidget(selected: selectedIndex != null),
              label: d.label,
            ),
        ],
      ),
    );
  }
}

/// Tracks scroll direction for [HidingNavigationBar].
class HideOnScroll extends ValueNotifier<bool> {
  HideOnScroll() : super(true);

  Widget listener({required Widget child}) =>
      NotificationListener<UserScrollNotification>(
        onNotification: (n) {
          if (n.depth != 0) return false;
          if (n.direction == ScrollDirection.reverse) value = false;
          if (n.direction == ScrollDirection.forward) value = true;
          return false;
        },
        child: child,
      );
}

/// The M3 Expressive navigation rail on Flutter's [NavigationRail]:
/// collapsed 96dp with labels under icons, or expanded (240dp+) with
/// labels beside icons. A menu button at the top switches between them;
/// an optional FAB sits under it. Collapsed shows [primary] only, expanded
/// adds [secondary]. Its content scrolls when it does not fit.
class TashilNavigationRail extends StatelessWidget {
  const TashilNavigationRail({
    super.key,
    required this.primary,
    this.secondary = const [],
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.expanded,
    this.onMenu,
    this.fab,
    this.expandedWidth = 240,
    this.backgroundColor,
  });

  final List<TashilDestination> primary;
  final List<TashilDestination> secondary;

  /// Index across [primary] then [secondary].
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final bool expanded;

  /// Toggles [expanded]; for the modal rail it closes it.
  final VoidCallback? onMenu;
  final ({IconData icon, String label, VoidCallback onPressed})? fab;
  final double expandedWidth;
  final Color? backgroundColor;

  /// M3 Expressive collapsed rail width.
  static const collapsedWidth = 96.0;

  @override
  Widget build(BuildContext context) {
    final l = MaterialLocalizations.of(context);
    final shown = expanded ? [...primary, ...secondary] : primary;
    final f = fab;
    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: c.maxHeight),
          child: IntrinsicHeight(
            child: NavigationRail(
              extended: expanded,
              minWidth: collapsedWidth,
              minExtendedWidth: expandedWidth,
              backgroundColor: backgroundColor,
              groupAlignment: -1,
              labelType: expanded
                  ? NavigationRailLabelType.none
                  : NavigationRailLabelType.all,
              selectedIndex: selectedIndex < shown.length
                  ? selectedIndex
                  : null,
              onDestinationSelected: onDestinationSelected,
              leading: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (onMenu != null)
                    Padding(
                      padding: EdgeInsetsDirectional.only(
                        start: expanded ? TashilSpacing.lg : 0,
                      ),
                      child: IconButton(
                        tooltip: expanded
                            ? l.closeButtonTooltip
                            : l.openAppDrawerTooltip,
                        icon: Icon(expanded ? Icons.menu_open : Icons.menu),
                        onPressed: onMenu,
                      ),
                    ),
                  if (f != null) ...[
                    const SizedBox(height: TashilSpacing.sm),
                    Padding(
                      padding: EdgeInsetsDirectional.only(
                        start: expanded ? TashilSpacing.lg : 0,
                      ),
                      child: expanded
                          ? FloatingActionButton.extended(
                              heroTag: null,
                              elevation: 0,
                              onPressed: f.onPressed,
                              icon: Icon(f.icon),
                              label: Text(f.label),
                            )
                          : FloatingActionButton(
                              heroTag: null,
                              elevation: 0,
                              tooltip: f.label,
                              onPressed: f.onPressed,
                              child: Icon(f.icon),
                            ),
                    ),
                  ],
                  const SizedBox(height: TashilSpacing.sm),
                ],
              ),
              destinations: [
                for (final d in shown)
                  NavigationRailDestination(
                    icon: d.iconWidget(),
                    selectedIcon: d.iconWidget(selected: true),
                    label: Text(d.label),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// App shell that picks the navigation for the breakpoint (M3 adaptive
/// design): bar on compact, collapsed rail on medium and expanded, expanded
/// rail from large (1200dp). The person can expand or collapse the rail
/// with its menu button. Secondary destinations are in the modal rail on
/// compact. A medium layout with two panes keeps the bar
/// ([barOnMedium]) so the panes get the full width.
class AdaptiveNavigationScaffold extends StatefulWidget {
  const AdaptiveNavigationScaffold({
    super.key,
    required this.title,
    required this.primary,
    this.secondary = const [],
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.body,
    this.fab,
    this.barOnMedium = false,
    this.actions = const [],
    this.toolbar = const [],
  }) : assert(primary.length >= 3 && primary.length <= 5),
       assert(actions.length <= 2, 'M3 bars: 1 to 2 essential actions');

  final String title;

  /// 3 to 5 main destinations: in the bar and the collapsed rail.
  final List<TashilDestination> primary;

  /// Only in the expanded rail (customers, suppliers, expenses...).
  final List<TashilDestination> secondary;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget body;
  final ({IconData icon, String label, VoidCallback onPressed})? fab;

  /// Medium screen showing two panes: navigation bar instead of the rail.
  final bool barOnMedium;

  /// App bar actions: at most two essential ones (search, scan). The rest
  /// go in an overflow menu or the [toolbar].
  final List<Widget> actions;

  /// Actions for this screen in the rail region (M3 scaffold > rails): a
  /// horizontal [TashilToolbar] floating above the navigation bar on
  /// compact, a vertical one in the trailing rail from medium. Empty = none.
  final List<ToolbarAction> toolbar;

  /// Width of the trailing rail region that holds the vertical toolbar.
  static const trailingRailWidth = 88.0;

  /// From this width (the large breakpoint) the rail starts expanded.
  static const expandedFrom = 1200.0;

  @override
  State<AdaptiveNavigationScaffold> createState() =>
      _AdaptiveNavigationScaffoldState();
}

class _AdaptiveNavigationScaffoldState
    extends State<AdaptiveNavigationScaffold> {
  final _bar = HideOnScroll();
  bool? _expanded;

  @override
  void dispose() {
    _bar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = widget;
        if (c.maxWidth < TashilSizes.compactMax) return _compact();
        if (w.barOnMedium && c.maxWidth < TashilSizes.mediumMax) {
          return _compact();
        }
        final expanded =
            _expanded ?? c.maxWidth >= AdaptiveNavigationScaffold.expandedFrom;
        const expandedWidth = 240.0;
        return Scaffold(
          body: Row(
            children: [
              TashilNavigationRail(
                primary: w.primary,
                secondary: w.secondary,
                selectedIndex: w.selectedIndex,
                onDestinationSelected: w.onDestinationSelected,
                expanded: expanded,
                expandedWidth: expandedWidth,
                onMenu: () => setState(() => _expanded = !expanded),
                fab: w.fab,
              ),
              Expanded(
                child: Scaffold(
                  appBar: AppBar(title: Text(w.title), actions: w.actions),
                  // Panes need the rail width to keep a split layout's
                  // spacer centred in the window.
                  body: NavigationInset(
                    width: expanded
                        ? expandedWidth
                        : TashilNavigationRail.collapsedWidth,
                    child: w.body,
                  ),
                ),
              ),
              if (w.toolbar.isNotEmpty)
                SizedBox(
                  width: AdaptiveNavigationScaffold.trailingRailWidth,
                  child: Center(
                    child: TashilToolbar(
                      axis: Axis.vertical,
                      actions: w.toolbar,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _compact() {
    final w = widget;
    final f = w.fab;
    final inBar = w.selectedIndex < w.primary.length;
    return Scaffold(
      appBar: AppBar(title: Text(w.title), actions: w.actions),
      drawer: w.secondary.isEmpty
          ? null
          : Builder(
              builder: (context) => ModalNavigationRail(
                primary: w.primary,
                secondary: w.secondary,
                selectedIndex: w.selectedIndex,
                onDestinationSelected: w.onDestinationSelected,
              ),
            ),
      body: _bar.listener(
        child: w.toolbar.isEmpty
            ? w.body
            : Stack(
                children: [
                  Positioned.fill(child: w.body),
                  // Bottom rail region: floats above the navigation bar.
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: TashilSpacing.lg,
                    child: Center(child: TashilToolbar(actions: w.toolbar)),
                  ),
                ],
              ),
      ),
      floatingActionButton: f == null
          ? null
          : FloatingActionButton(
              heroTag: null,
              tooltip: f.label,
              onPressed: f.onPressed,
              child: Icon(f.icon),
            ),
      bottomNavigationBar: HidingNavigationBar(
        visible: _bar,
        destinations: w.primary,
        selectedIndex: inBar ? w.selectedIndex : null,
        onDestinationSelected: w.onDestinationSelected,
      ),
    );
  }
}

/// The expanded rail as a modal over the content, for compact windows
/// (replaces the modal navigation drawer). Use as [Scaffold.drawer]: the
/// scrim, swipe and back-to-close come from Flutter's [Drawer].
class ModalNavigationRail extends StatelessWidget {
  const ModalNavigationRail({
    super.key,
    required this.primary,
    this.secondary = const [],
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final List<TashilDestination> primary;
  final List<TashilDestination> secondary;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: 280,
      child: SafeArea(
        child: TashilNavigationRail(
          primary: primary,
          secondary: secondary,
          selectedIndex: selectedIndex,
          expanded: true,
          expandedWidth: 280,
          backgroundColor: Colors.transparent,
          onMenu: () => Navigator.pop(context),
          onDestinationSelected: (i) {
            Navigator.pop(context);
            onDestinationSelected(i);
          },
        ),
      ),
    );
  }
}
