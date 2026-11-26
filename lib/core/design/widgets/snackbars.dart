import 'package:material_ui/material_ui.dart';

import '../tokens.dart';

/// Snackbars that follow m3.material.io/components/snackbar/guidelines,
/// on Flutter's official [SnackBar] and [ScaffoldMessenger]:
///
/// * Low priority, short update about something the app did ("اتبعت
///   للطابعة"). Anything that needs a decision is a dialog.
/// * Text only: no icons, no links, no styled text. One line when
///   possible, two at most on phones.
/// * At most one text action (usually "تراجع"); never a filled button.
///   Without an action it disappears after 4 seconds. With an action it
///   stays until used or closed, so it also gets a close button.
/// * One at a time. Newer information replaces an outdated snackbar
///   straight away; snackbars never stack.
/// * Floating (from the theme): above the FAB and the navigation bar,
///   never in front of them. From 600dp it is centred with a width that
///   fits about 40 to 60 characters, never flush to an edge.
/// * Also show the result where the action happened (the button says
///   "اتحفظ"), so people who miss the snackbar still get it.
ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showTashilSnackBar(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
  bool replace = true,
}) {
  assert((actionLabel == null) == (onAction == null));
  final messenger = ScaffoldMessenger.of(context);
  if (replace) messenger.removeCurrentSnackBar();
  final width = MediaQuery.sizeOf(context).width;
  final hasAction = actionLabel != null;
  return messenger.showSnackBar(
    SnackBar(
      content: Text(message, maxLines: 2, overflow: TextOverflow.ellipsis),
      action: hasAction
          ? SnackBarAction(label: actionLabel, onPressed: onAction!)
          : null,
      // M3: with an action it stays until acted on or closed.
      persist: hasAction,
      showCloseIcon: hasAction,
      width: width < TashilSizes.compactMax
          ? null
          : (width - 2 * TashilSpacing.xl).clamp(0, 560),
    ),
  );
}
