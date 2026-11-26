import 'package:animations/animations.dart';
import 'package:material_ui/material_ui.dart';

import '../motion.dart';
import '../tokens.dart';

/// Dialog helpers that follow m3.material.io/components/dialogs/guidelines.
/// They only arrange official widgets ([AlertDialog], [Dialog.fullscreen],
/// [PopScope]) and Google's `animations` package.
///
/// Rules (see docs/design-system.md, "Dialogs"):
/// * Dialogs are for high-importance prompts that block the task. Low
///   priority information is a [SnackBar].
/// * Headline: a short, clear statement or question. No "هل أنت متأكد؟".
/// * Text buttons. At most two actions: the confirming one says what
///   happens ("إلغاء الفاتورة", "حفظ"), never "تمام" unless the dialog only
///   acknowledges. Confirm sits at the end (left in Arabic), dismiss before
///   it. Dismiss is never disabled; confirm is disabled until a choice.
/// * Errors in fields appear inline; only a failed save gets a dialog.

/// Opens a basic dialog with the M3 **enter and exit** pattern
/// (fade + scale, [FadeScaleTransition]) instead of Flutter's plain fade.
Future<T?> showTashilDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  return showModal<T>(
    context: context,
    configuration: FadeScaleTransitionConfiguration(
      barrierDismissible: barrierDismissible,
      transitionDuration: reduce
          ? Duration.zero
          : TashilEasing.emphasizedDecelerate.duration ~/ 2,
      reverseTransitionDuration: reduce
          ? Duration.zero
          : TashilEasing.emphasizedAccelerate.duration ~/ 2,
    ),
    builder: builder,
  );
}

/// "Discard unsaved changes?" asked when a full-screen dialog is closed
/// with edits. Returns true when the person chose to discard.
Future<bool> confirmDiscard(BuildContext context) async {
  final r = await showTashilDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('تتجاهل التعديلات؟'),
      content: const Text('التعديلات اللي ما اتحفظتش هتضيع.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: const Text('كمّل تعديل'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(c, true),
          child: const Text('تجاهل'),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// A form in a dialog, adaptive per M3:
/// * compact (< 600dp, SUNMI): full-screen dialog, ✕ to close, the save
///   action named in the app bar;
/// * medium and up: the same form as a basic dialog.
///
/// Closing with unsaved edits ([dirty]) asks [confirmDiscard] first, for
/// the ✕, the system back button and the dismiss action alike.
class FormDialog extends StatelessWidget {
  const FormDialog({
    super.key,
    required this.title,
    required this.saveLabel,
    required this.onSave,
    required this.dirty,
    required this.child,
    this.saving = false,
  });

  final String title;

  /// Says what happens: "حفظ", "إضافة الصنف". Not "تمام".
  final String saveLabel;
  final VoidCallback onSave;
  final bool dirty;
  final bool saving;
  final Widget child;

  Future<void> _close(BuildContext context) async {
    if (!dirty || await confirmDiscard(context)) {
      if (context.mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < TashilSizes.compactMax;
    final save = saving
        ? const Padding(
            padding: EdgeInsets.all(TashilSpacing.md),
            child: SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
          )
        : TextButton(onPressed: onSave, child: Text(saveLabel));

    final body = PopScope(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close(context);
      },
      child: compact
          ? Dialog.fullscreen(
              child: Scaffold(
                appBar: AppBar(
                  leading: CloseButton(onPressed: () => _close(context)),
                  title: Text(title),
                  actions: [
                    save,
                    const SizedBox(width: TashilSpacing.sm),
                  ],
                ),
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(TashilSpacing.page),
                  child: child,
                ),
              ),
            )
          : AlertDialog(
              title: Text(title),
              scrollable: true,
              content: SizedBox(width: 400, child: child),
              actions: [
                TextButton(
                  onPressed: () => _close(context),
                  child: Text(
                    MaterialLocalizations.of(context).cancelButtonLabel,
                  ),
                ),
                save,
              ],
            ),
    );
    return body;
  }
}

/// Basic dialog for picking one item from a list (M3 "quick selection").
/// The headline and buttons stay pinned while the list scrolls, with
/// dividers; the confirm button is disabled until something is chosen.
Future<T?> showChoiceDialog<T>({
  required BuildContext context,
  required String title,
  required String confirmLabel,
  required Map<T, String> options,
  T? initial,
}) {
  return showTashilDialog<T>(
    context: context,
    builder: (c) {
      T? chosen = initial;
      return StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(title),
          contentPadding: const EdgeInsets.only(top: TashilSpacing.md),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Divider(),
                Flexible(
                  child: RadioGroup<T>(
                    groupValue: chosen,
                    onChanged: (v) => set(() => chosen = v),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final e in options.entries)
                          RadioListTile<T>(value: e.key, title: Text(e.value)),
                      ],
                    ),
                  ),
                ),
                const Divider(),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: Text(MaterialLocalizations.of(c).cancelButtonLabel),
            ),
            TextButton(
              onPressed: chosen == null ? null : () => Navigator.pop(c, chosen),
              child: Text(confirmLabel),
            ),
          ],
        ),
      );
    },
  );
}
