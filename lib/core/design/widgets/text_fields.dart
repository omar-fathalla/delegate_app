import 'package:material_ui/material_ui.dart';

import '../tokens.dart';

/// How a [TashilTextField] shows long input (M3 "Input text").
enum TextFieldLines {
  /// One line; longer text scrolls sideways. Names, prices, barcodes.
  single,

  /// Starts as one line and grows (up to [TashilTextField.maxLines]),
  /// pushing what is below it down. Short notes in compact layouts.
  multi,

  /// A taller fixed-height box that scrolls inside. Tells people a longer
  /// answer is welcome (return reason, supplier notes).
  area,
}

/// A text field that follows m3.material.io/components/text-fields/
/// guidelines, built on Flutter's official [TextField] with the outlined
/// look from the theme:
///
/// * Every field has a label (unless an adjacent label sits at its
///   leading edge). Short, one line, never cut.
/// * Required fields get an asterisk after the label; put one
///   [RequiredFieldsNote] at the top of the form to explain it.
/// * Error text replaces the supporting text (it never adds a line), and
///   an error icon is always shown with it.
/// * Optional valid icon, and a clear icon that appears only while there
///   is text.
/// * Character counter when there is a limit ([maxLength]).
/// * Prefix and suffix text (units, country code). In Arabic the
///   currency goes after the amount, so it is a suffix.
/// * Read-only fields look like normal fields and say they are read-only.
class TashilTextField extends StatefulWidget {
  const TashilTextField({
    super.key,
    required this.label,
    this.controller,
    this.isRequired = false,
    this.supportingText,
    this.errorText,
    this.valid = false,
    this.leadingIcon,
    this.trailing,
    this.prefixText,
    this.suffixText,
    this.clearable = false,
    this.maxLength,
    this.lines = TextFieldLines.single,
    this.maxLines = 4,
    this.readOnly = false,
    this.enabled = true,
    this.keyboardType,
    this.textDirection,
    this.onChanged,
  });

  final String label;
  final TextEditingController? controller;
  final bool isRequired;
  final String? supportingText;

  /// When set, replaces [supportingText] and shows the error icon.
  final String? errorText;

  /// Shows a check icon (a second cue besides colour).
  final bool valid;
  final IconData? leadingIcon;

  /// A trailing icon button (scan, open a picker). Error, valid and clear
  /// icons take its place while they show.
  final Widget? trailing;
  final String? prefixText;
  final String? suffixText;
  final bool clearable;
  final int? maxLength;
  final TextFieldLines lines;

  /// Highest number of lines for [TextFieldLines.multi], and the fixed
  /// height in lines for [TextFieldLines.area].
  final int maxLines;
  final bool readOnly;
  final bool enabled;
  final TextInputType? keyboardType;

  /// For values read left to right (phone numbers, barcodes).
  final TextDirection? textDirection;
  final ValueChanged<String>? onChanged;

  @override
  State<TashilTextField> createState() => _TashilTextFieldState();
}

class _TashilTextFieldState extends State<TashilTextField> {
  TextEditingController? _own;
  TextEditingController get _c =>
      widget.controller ?? (_own ??= TextEditingController());

  @override
  void initState() {
    super.initState();
    _c.addListener(_changed);
  }

  @override
  void didUpdateWidget(TashilTextField old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      (old.controller ?? _own)?.removeListener(_changed);
      _c.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _c.removeListener(_changed);
    _own?.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  Widget? _trailing(ColorScheme scheme) {
    if (widget.errorText != null) {
      return Icon(Icons.error, color: scheme.error, semanticLabel: 'خطأ');
    }
    if (widget.valid) {
      return Icon(
        Icons.check_circle,
        color:
            Theme.of(context).extension<TashilSemanticColors>()?.success ??
            TashilColors.success,
        semanticLabel: 'صحيح',
      );
    }
    if (widget.clearable &&
        !widget.readOnly &&
        widget.enabled &&
        _c.text.isNotEmpty) {
      return IconButton(
        tooltip: 'مسح',
        icon: const Icon(Icons.cancel_outlined),
        onPressed: () {
          _c.clear();
          widget.onChanged?.call('');
        },
      );
    }
    return widget.trailing;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final w = widget;
    final pageDirection = Directionality.of(context);
    final supporting =
        w.supportingText ?? (w.readOnly ? 'للقراءة بس، مش بيتعدّل' : null);
    final (minLines, maxLines) = switch (w.lines) {
      TextFieldLines.single => (1, 1),
      TextFieldLines.multi => (1, w.maxLines),
      TextFieldLines.area => (w.maxLines, w.maxLines),
    };
    return TextField(
      controller: _c,
      readOnly: w.readOnly,
      enabled: w.enabled,
      keyboardType:
          w.keyboardType ??
          (w.lines == TextFieldLines.single ? null : TextInputType.multiline),
      textDirection: w.textDirection,
      minLines: minLines,
      maxLines: maxLines,
      maxLength: w.maxLength,
      onChanged: w.onChanged,
      decoration: InputDecoration(
        label: w.isRequired ? RequiredLabel(w.label) : Text(w.label),
        // Supporting and error text follow the page direction, also when
        // the value itself is read left to right ([textDirection]).
        helper: supporting == null
            ? null
            : Text(supporting, textDirection: pageDirection),
        error: w.errorText == null
            ? null
            : Text(
                w.errorText!,
                textDirection: pageDirection,
                maxLines: 2,
                style: TextStyle(color: scheme.error),
              ),
        prefixIcon: w.leadingIcon == null ? null : Icon(w.leadingIcon),
        suffixIcon: _trailing(scheme),
        prefixText: w.prefixText,
        suffixText: w.suffixText,
        alignLabelWithHint: w.lines == TextFieldLines.area,
      ),
    );
  }
}

/// A label with the required asterisk. Read out as "مطلوب", not "star".
class RequiredLabel extends StatelessWidget {
  const RequiredLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$text، مطلوب',
    excludeSemantics: true,
    child: Text('$text *', maxLines: 1),
  );
}

/// One note at the top of a form that explains the asterisk (M3: explain
/// it once, either here or in supporting text).
class RequiredFieldsNote extends StatelessWidget {
  const RequiredFieldsNote({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: TashilSpacing.md),
    child: Text(
      'العلامة * معناها إن الحقل مطلوب',
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );
}

/// Lays out a form's fields: full width on compact windows; from 600dp
/// the fields stop at [maxWidth] and stay at the start edge, so they never
/// stretch across a large screen.
class FormColumn extends StatelessWidget {
  const FormColumn({
    super.key,
    required this.children,
    this.maxWidth = 560,
    this.gap = TashilSpacing.lg,
  });

  final List<Widget> children;
  final double maxWidth;
  final double gap;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.topStart,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, c) in children.indexed) ...[
            if (i > 0) SizedBox(height: gap),
            c,
          ],
        ],
      ),
    ),
  );
}
