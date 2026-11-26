import 'package:material_ui/material_ui.dart';

import '../design/widgets/snackbars.dart';

/// App-wide short messages. Since TAS-352 every call goes through the
/// design system's [showTashilSnackBar] (m3-kit C-30): text only, no icon,
/// no error / primary fill, one at a time, gone after 4 seconds. The three
/// names stay so the 150+ call sites keep working; they no longer look
/// different, because M3 snackbars carry no status colour (an error that
/// needs attention belongs in the screen or a dialog, not a red snackbar).
class AppSnackBar {
  AppSnackBar._();

  static String _clean(String message) {
    // Strip common Unicode emojis (such as ✅, ❌, ⚠️, ↩, etc.) so only clean
    // text is displayed.
    return message
        .replaceAll(
          RegExp(
            r'[\u{1F300}-\u{1F9FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}\u{FE00}-\u{FE0F}\u{1FA00}-\u{1FAFF}]',
            unicode: true,
          ),
          '',
        )
        .trim();
  }

  static void _show(BuildContext context, String message) {
    if (!context.mounted) return;
    showTashilSnackBar(context, _clean(message));
  }

  static void showError(BuildContext context, String message) =>
      _show(context, message);

  static void showSuccess(BuildContext context, String message) =>
      _show(context, message);

  static void showInfo(BuildContext context, String message) =>
      _show(context, message);
}
