import 'package:flutter/material.dart';

import 'package:delegate_app/features/hr/presentation/hr_design_tokens.dart';

/// Inner pages of the web HR shell (TAS-136).
///
/// On a wide web window [HRMainScreen] puts its content area in a nested
/// [Navigator] and publishes an [HrInnerPageHost]. Pages pushed with
/// [pushHrInnerPage] then open inside the content area: the sidebar and top
/// bar stay, and the page gets a breadcrumb («الصفحة › الصفحة الداخلية»),
/// a back button and a max content width. Without a host (mobile, narrow
/// web, tests) the page is pushed full screen as before.

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
Future<T?> pushHrInnerPage<T>(
  BuildContext context, {
  required String title,
  required Widget Function(BuildContext context, bool inShell) builder,
  double maxWidth = HrInnerPageWidth.form,
}) {
  final host = HrInnerPageHost.maybeOf(context);
  final nav = host?.navigatorKey.currentState;
  if (host == null || nav == null) {
    return Navigator.of(
      context,
    ).push<T>(MaterialPageRoute(builder: (ctx) => builder(ctx, false)));
  }
  final parentTitle = host.parentTitle;
  return nav.push<T>(
    PageRouteBuilder<T>(
      settings: RouteSettings(name: '$kHrInnerRoutePrefix$title'),
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
