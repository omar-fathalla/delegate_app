import 'package:flutter/material.dart';

import 'package:delegate_app/features/hr/presentation/hr_design_tokens.dart';

/// Inner pages of the web HR shell (TAS-136).
///
/// On a wide web window [HRMainScreen] puts its content area in a nested
/// [Navigator] and publishes an [HrInnerPageHost]. Pages pushed with
/// [pushHrInnerPage] then open inside the content area: the sidebar and top
/// bar stay, and the page gets a breadcrumb («الصفحة › الصفحة الداخلية»),
/// a back button and a max content width. Without a host (mobile, narrow
/// web, tests) the page is pushed full screen as before. On narrow web the
/// shell publishes an [HrInnerPageTracker] instead, so the full-screen page
/// is still counted in the URL and the browser back button closes it
/// (TAS-189).

/// Content widths for inner pages.
abstract final class HrInnerPageWidth {
  /// Forms (add delegate, create task, settings).
  static const double form = 720;

  /// Reports and logs that need more room.
  static const double wide = 1200;
}

/// Route-name prefix of inner pages. The shell counts these routes to keep
/// `?inner=<n>` in the URL, so the browser back button closes them
/// (TAS-139). Popups on the same navigator (menus, sheets) are not counted.
const String kHrInnerRoutePrefix = 'hr-inner:';

/// Whether [route] is an inner page pushed by [pushHrInnerPage].
bool isHrInnerRoute(Route<dynamic> route) =>
    route.settings.name?.startsWith(kHrInnerRoutePrefix) ?? false;

/// URL part of an inner page that has its own address (TAS-190), relative
/// to the shell page: `delegate/<id>` gives `/hr/<tab>/delegate/<id>`.
/// Stored in the route's [RouteSettings.arguments].
class HrInnerPageUrl {
  const HrInnerPageUrl(this.path);

  final String path;
}

/// The [HrInnerPageUrl.path] of an inner [route], or null.
String? hrInnerRouteUrl(Route<dynamic> route) {
  final args = route.settings.arguments;
  return args is HrInnerPageUrl ? args.path : null;
}

/// Published by the narrow web shell, which has no inner navigator
/// (TAS-189). [pushHrInnerPage] then pushes the page full screen and reports
/// it here, so the shell can count it in the URL (`?inner=<n>`) and close it
/// when the browser back button shortens the URL. Mobile never publishes it.
class HrInnerPageTracker extends InheritedWidget {
  const HrInnerPageTracker({
    super.key,
    required this.onOpened,
    required this.onClosed,
    required super.child,
  });

  /// A full-screen inner page was pushed.
  final void Function(Route<dynamic> route) onOpened;

  /// A full-screen inner page left its navigator (popped or removed).
  final void Function(Route<dynamic> route) onClosed;

  static HrInnerPageTracker? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HrInnerPageTracker>();

  @override
  bool updateShouldNotify(HrInnerPageTracker oldWidget) =>
      onOpened != oldWidget.onOpened || onClosed != oldWidget.onClosed;
}

/// Full-screen inner page on narrow web: reports its close once, as soon as
/// the navigator pops or removes it.
class _TrackedInnerPageRoute<T> extends MaterialPageRoute<T> {
  _TrackedInnerPageRoute({
    required super.builder,
    required super.settings,
    required this.onClosed,
  });

  final void Function(Route<dynamic> route) onClosed;
  bool _reported = false;

  void _report() {
    if (_reported) return;
    _reported = true;
    onClosed(this);
  }

  @override
  void didComplete(T? result) {
    super.didComplete(result);
    _report();
  }

  @override
  void dispose() {
    _report();
    super.dispose();
  }
}

/// Published by the web shell while its content area has a nested navigator.
class HrInnerPageHost extends InheritedWidget {
  const HrInnerPageHost({
    super.key,
    required this.navigatorKey,
    required this.parentTitle,
    required super.child,
  });

  /// The nested navigator of the shell's content area.
  final GlobalKey<NavigatorState> navigatorKey;

  /// Title of the shell page the inner page was opened from (the first
  /// breadcrumb item).
  final String parentTitle;

  static HrInnerPageHost? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HrInnerPageHost>();

  @override
  bool updateShouldNotify(HrInnerPageHost oldWidget) =>
      parentTitle != oldWidget.parentTitle ||
      navigatorKey != oldWidget.navigatorKey;
}

/// Opens an inner page.
///
/// [builder] receives `inShell`: true when the page is shown inside the web
/// shell, where it must not draw its own app bar (the breadcrumb already
/// carries the title and the back button). When false the page is pushed
/// full screen and should keep its app bar.
///
/// [urlPath] gives the page its own web address under the shell page
/// (TAS-190), for example `delegate/<id>`. Ids only, never names or other
/// personal data.
Future<T?> pushHrInnerPage<T>(
  BuildContext context, {
  required String title,
  required Widget Function(BuildContext context, bool inShell) builder,
  double maxWidth = HrInnerPageWidth.form,
  String? urlPath,
}) {
  final settings = RouteSettings(
    name: '$kHrInnerRoutePrefix$title',
    arguments: urlPath == null ? null : HrInnerPageUrl(urlPath),
  );
  final host = HrInnerPageHost.maybeOf(context);
  final nav = host?.navigatorKey.currentState;
  if (host == null || nav == null) {
    final tracker = HrInnerPageTracker.maybeOf(context);
    if (tracker == null) {
      return Navigator.of(
        context,
      ).push<T>(MaterialPageRoute(builder: (ctx) => builder(ctx, false)));
    }
    // Narrow web (TAS-189): full screen as before, but counted in the URL.
    final route = _TrackedInnerPageRoute<T>(
      settings: settings,
      builder: (ctx) => builder(ctx, false),
      onClosed: tracker.onClosed,
    );
    final opened = Navigator.of(context).push<T>(route);
    tracker.onOpened(route);
    return opened;
  }
  final parentTitle = host.parentTitle;
  return nav.push<T>(
    PageRouteBuilder<T>(
      settings: settings,
      transitionDuration: const Duration(milliseconds: 200),
      reverseTransitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (ctx, _, _) => HrInnerPage(
        parentTitle: parentTitle,
        title: title,
        maxWidth: maxWidth,
        child: Builder(builder: (inner) => builder(inner, true)),
      ),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

/// Breadcrumb, back button and width-limited content of an inner page.
class HrInnerPage extends StatelessWidget {
  const HrInnerPage({
    super.key,
    required this.parentTitle,
    required this.title,
    required this.child,
    this.maxWidth = HrInnerPageWidth.form,
  });

  final String parentTitle;
  final String title;
  final double maxWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final nav = Navigator.of(context);
    return Material(
      color: cs.surfaceContainerLowest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 24, 4),
            child: Row(
              key: const ValueKey('hr_inner_page_breadcrumb'),
              children: [
                IconButton(
                  key: const ValueKey('hr_inner_page_back'),
                  tooltip: 'رجوع',
                  onPressed: () => nav.maybePop(),
                  icon: const BackButtonIcon(),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: TextButton(
                    key: const ValueKey('hr_inner_page_parent'),
                    onPressed: () => nav.popUntil((r) => r.isFirst),
                    style: TextButton.styleFrom(
                      foregroundColor: cs.onSurfaceVariant,
                      textStyle: theme.textTheme.titleSmall,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(HrRadius.chip),
                      ),
                    ),
                    child: Text(
                      parentTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                // Mirrors with the text direction (points left in RTL).
                Icon(Icons.chevron_right, size: 20, color: cs.onSurfaceVariant),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    title,
                    key: const ValueKey('hr_inner_page_title'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                key: const ValueKey('hr_inner_page_content'),
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
