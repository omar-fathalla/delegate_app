import 'package:material_ui/material_ui.dart';

import 'package:delegate_app/config/theme/app_motion.dart';
import 'package:delegate_app/core/platform/web_runtime_policy.dart';
import 'package:delegate_app/features/hr/presentation/hr_design_tokens.dart';

/// How an [showHrAdaptiveSheet] opens on a wide web window.
enum HrSheetKind {
  /// Centered dialog. For short forms (a few fields, a confirmation).
  dialog,

  /// Full-height side sheet from the reading end (left in RTL). For long
  /// forms and lists.
  side,
}

/// Shared measures of HR sheets and dialogs (TAS-137).
abstract final class HrSheet {
  /// Every HR side sheet has this width (notifications, add chains, forms).
  static const double sideWidth = 440;

  /// Default max width of an HR dialog.
  static const double dialogWidth = 560;

  /// Below this window width the web falls back to the mobile bottom sheet.
  static const double compactBelow = 600;

  /// True when [context] should get a dialog or side sheet instead of a
  /// bottom sheet: web, and the window is wider than [compactBelow].
  static bool useDesktop(BuildContext context) =>
      WebRuntimePolicy.isWeb &&
      MediaQuery.sizeOf(context).width >= compactBelow;
}

/// One entry point for HR forms that used to open a bottom sheet (TAS-137).
///
/// * Mobile, and narrow web windows: a modal bottom sheet with a drag
///   handle, as before.
/// * Wide web: a dialog ([HrSheetKind.dialog]) or a side sheet
///   ([HrSheetKind.side]) that opens from the reading end.
///
/// [builder] builds the body only. The frame adds the [title], a close
/// button and, when [actions] is given, a footer with the buttons. The body
/// is scrollable, so it should not contain its own unbounded scroll view at
/// the top level unless [scrollBody] is false.
Future<T?> showHrAdaptiveSheet<T>({
  required BuildContext context,
  required String title,
  required WidgetBuilder builder,
  List<Widget> Function(BuildContext sheetContext)? actions,
  HrSheetKind webKind = HrSheetKind.dialog,
  double dialogWidth = HrSheet.dialogWidth,
  bool scrollBody = true,
  bool barrierDismissible = true,
  bool useRootNavigator = true,
}) {
  if (!HrSheet.useDesktop(context)) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      useRootNavigator: useRootNavigator,
      isDismissible: barrierDismissible,
      builder: (sheetContext) => HrSheetFrame(
        title: title,
        layout: HrSheetLayout.bottom,
        scrollBody: scrollBody,
        actions: actions?.call(sheetContext),
        child: builder(sheetContext),
      ),
    );
  }

  if (webKind == HrSheetKind.dialog) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      useRootNavigator: useRootNavigator,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HrRadius.pill),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: dialogWidth,
            maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.85,
          ),
          child: HrSheetFrame(
            title: title,
            layout: HrSheetLayout.dialog,
            scrollBody: scrollBody,
            actions: actions?.call(dialogContext),
            child: builder(dialogContext),
          ),
        ),
      ),
    );
  }

  return showHrSideSheet<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    useRootNavigator: useRootNavigator,
    barrierLabel: 'إغلاق $title',
    builder: (sheetContext) => HrSheetFrame(
      title: title,
      layout: HrSheetLayout.side,
      scrollBody: scrollBody,
      actions: actions?.call(sheetContext),
      child: builder(sheetContext),
    ),
  );
}

/// Opens [builder] as a full-height side sheet from the reading end (the
/// left edge in RTL, the right edge in LTR), [HrSheet.sideWidth] wide.
///
/// Use it for sheets that draw their own content frame. Forms should prefer
/// [showHrAdaptiveSheet], which also handles mobile.
Future<T?> showHrSideSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  String barrierLabel = 'إغلاق',
  bool barrierDismissible = true,
  bool useRootNavigator = true,
  double width = HrSheet.sideWidth,
}) {
  final direction = Directionality.of(context);
  return Navigator.of(context, rootNavigator: useRootNavigator).push<T>(
    HrSideSheetRoute<T>(
      barrierColor: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.32),
      dismissible: barrierDismissible,
      label: barrierLabel,
      builder: (ctx) => Directionality(
        textDirection: direction,
        child: HrSideSheetSurface(width: width, child: builder(ctx)),
      ),
    ),
  );
}

/// Popup route that slides a side sheet in from the reading end.
class HrSideSheetRoute<T> extends PopupRoute<T> {
  HrSideSheetRoute({
    required this.builder,
    required Color barrierColor,
    required bool dismissible,
    required String label,
    super.settings,
  }) : _barrierColor = barrierColor,
       _dismissible = dismissible,
       _label = label;

  final WidgetBuilder builder;
  final Color _barrierColor;
  final bool _dismissible;
  final String _label;

  @override
  Color get barrierColor => _barrierColor;

  @override
  bool get barrierDismissible => _dismissible;

  @override
  String get barrierLabel => _label;

  @override
  Duration get transitionDuration => AppMotionDurations.medium4;

  @override
  Duration get reverseTransitionDuration => AppMotionDurations.short4;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => builder(context);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return HrSideSheetTransition(animation: animation, child: child);
  }
}

/// Slides [child] in from the reading end of the current [Directionality].
class HrSideSheetTransition extends StatelessWidget {
  const HrSideSheetTransition({
    super.key,
    required this.animation,
    required this.child,
  });

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Offset.dx is physical. The reading end is the left in RTL.
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final curved = CurvedAnimation(
      parent: animation,
      curve: AppMotionCurves.emphasizedDecelerate,
      reverseCurve: AppMotionCurves.emphasizedAccelerate,
    );
    return SlideTransition(
      position: Tween<Offset>(
        begin: Offset(rtl ? -1 : 1, 0),
        end: Offset.zero,
      ).animate(curved),
      child: child,
    );
  }
}

/// Places [child] as a full-height panel at the reading end, with the inner
/// corners rounded.
class HrSideSheetSurface extends StatelessWidget {
  const HrSideSheetSurface({
    super.key,
    required this.child,
    this.width = HrSheet.sideWidth,
  });

  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final screen = MediaQuery.sizeOf(context).width;
    return Align(
      key: const ValueKey('hr_side_sheet'),
      alignment: AlignmentDirectional.centerEnd,
      child: SizedBox(
        width: width > screen ? screen : width,
        height: double.infinity,
        child: Material(
          color: cs.surfaceContainerLow,
          elevation: 1,
          clipBehavior: Clip.antiAlias,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadiusDirectional.horizontal(
              start: Radius.circular(HrRadius.card),
            ),
          ),
          child: SafeArea(child: child),
        ),
      ),
    );
  }
}

/// Where an [HrSheetFrame] is shown.
enum HrSheetLayout { bottom, dialog, side }

/// Title row with a close button, a scrollable body and an optional
/// actions footer. Shared by the bottom sheet, dialog and side sheet.
class HrSheetFrame extends StatelessWidget {
  const HrSheetFrame({
    super.key,
    required this.title,
    required this.child,
    this.actions,
    this.layout = HrSheetLayout.dialog,
    this.scrollBody = true,
  });

  final String title;
  final Widget child;
  final List<Widget>? actions;
  final HrSheetLayout layout;
  final bool scrollBody;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final side = layout == HrSheetLayout.side;
    final bottom = layout == HrSheetLayout.bottom;
    final pad = EdgeInsetsDirectional.only(
      start: 24,
      end: bottom ? 24 : 12,
      top: bottom ? 0 : 16,
      bottom: 8,
    );
    final body = scrollBody
        ? SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: child,
          )
        : Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: child,
          );
    final footer = actions;
    return Column(
      mainAxisSize: side ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: pad,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  key: const ValueKey('hr_sheet_title'),
                  style:
                      (bottom
                              ? theme.textTheme.titleMedium
                              : theme.textTheme.titleLarge)
                          ?.copyWith(color: cs.onSurface),
                ),
              ),
              if (!bottom)
                IconButton(
                  key: const ValueKey('hr_sheet_close'),
                  tooltip: 'إغلاق',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close_rounded),
                ),
            ],
          ),
        ),
        if (side) Expanded(child: body) else Flexible(child: body),
        if (footer != null && footer.isNotEmpty) ...[
          if (side) Divider(height: 1, color: cs.outlineVariant),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
            child: Wrap(
              key: const ValueKey('hr_sheet_actions'),
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: footer,
            ),
          ),
        ],
      ],
    );
  }
}
