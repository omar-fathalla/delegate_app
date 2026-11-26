import 'package:material_ui/material_ui.dart';

import '../tokens.dart';

/// M3 filter chip that opens a menu of options
/// (m3.material.io/components/chips/guidelines, "Filter chips").
///
/// The whole chip opens the menu, not only the ▾ icon, so the touch target
/// stays large on compact screens. Selected when a value is chosen; the menu
/// has a "الكل" entry that clears it.
class MenuFilterChip<T> extends StatelessWidget {
  const MenuFilterChip({
    super.key,
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
    this.allLabel = 'الكل',
  });

  /// Category name shown while nothing is selected (e.g. "التصنيف").
  final String label;
  final Map<T, String> options;
  final T? value;
  final ValueChanged<T?> onChanged;
  final String allLabel;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          onPressed: () => onChanged(null),
          leadingIcon: _check(value == null),
          child: Text(allLabel),
        ),
        for (final e in options.entries)
          MenuItemButton(
            onPressed: () => onChanged(e.key),
            leadingIcon: _check(value == e.key),
            child: Text(e.value),
          ),
      ],
      builder: (context, controller, _) => FilterChip(
        selected: value != null,
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(value == null ? label : options[value]!),
            const SizedBox(width: TashilSpacing.xs),
            const Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
        onSelected: (_) =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }

  static Widget _check(bool on) =>
      Icon(Icons.check, color: on ? null : Colors.transparent);
}

/// Text field that turns entries into M3 input chips
/// (m3.material.io/components/chips/guidelines, "Input chips").
///
/// * Enter, comma or Arabic comma turns the typed text into a chip.
/// * Backspace with the cursor before the text first selects the last chip,
///   a second Backspace deletes it. Works with the soft keyboard too: a
///   zero-width sentinel sits before the text so Android reports the key.
/// * Each chip has a ✕ to remove it.
class InputChipField extends StatefulWidget {
  const InputChipField({
    super.key,
    required this.values,
    required this.onChanged,
    this.label,
    this.hint,
    this.avatar,
  });

  final List<String> values;
  final ValueChanged<List<String>> onChanged;
  final String? label;
  final String? hint;

  /// Optional leading icon for every chip.
  final IconData? avatar;

  @override
  State<InputChipField> createState() => _InputChipFieldState();
}

class _InputChipFieldState extends State<InputChipField> {
  static const _sentinel = '​';
  final _controller = TextEditingController(text: _sentinel);
  final _focus = FocusNode(debugLabel: 'InputChipField');
  bool _lastArmed = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onText);
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _reset([String text = '']) {
    _controller.value = TextEditingValue(
      text: '$_sentinel$text',
      selection: TextSelection.collapsed(offset: 1 + text.length),
    );
  }

  void _onText() {
    final t = _controller.text;
    if (!t.startsWith(_sentinel)) {
      // The sentinel was deleted: Backspace at the start of the input.
      final rest = t.replaceAll(_sentinel, '');
      _backspace();
      _reset(rest);
      return;
    }
    // Keep the cursor after the sentinel.
    final sel = _controller.selection;
    if (sel.isValid && sel.baseOffset < 1) {
      _controller.selection = const TextSelection.collapsed(offset: 1);
    }
    final body = t.substring(1);
    if (body.endsWith(',') || body.endsWith('،')) {
      _add(body.substring(0, body.length - 1));
    } else {
      setState(() {
        if (body.isNotEmpty) _lastArmed = false;
      });
    }
  }

  void _backspace() {
    if (widget.values.isEmpty) return;
    if (_lastArmed) {
      setState(() => _lastArmed = false);
      widget.onChanged([...widget.values]..removeLast());
    } else {
      setState(() => _lastArmed = true);
    }
  }

  void _add(String raw) {
    final v = raw.trim();
    _reset();
    if (v.isEmpty || widget.values.contains(v)) return;
    setState(() => _lastArmed = false);
    widget.onChanged([...widget.values, v]);
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.values.length;
    return GestureDetector(
      onTap: _focus.requestFocus,
      child: InputDecorator(
        isFocused: _focus.hasFocus,
        isEmpty: n == 0 && _controller.text.length <= 1,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          contentPadding: const EdgeInsets.all(TashilSpacing.sm),
        ),
        child: Wrap(
          spacing: TashilSpacing.sm,
          runSpacing: TashilSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (var i = 0; i < n; i++)
              InputChip(
                avatar: widget.avatar == null ? null : Icon(widget.avatar),
                label: Text(widget.values[i]),
                selected: _lastArmed && i == n - 1,
                showCheckmark: false,
                onPressed: () {},
                onDeleted: () {
                  setState(() => _lastArmed = false);
                  widget.onChanged([...widget.values]..removeAt(i));
                },
                deleteButtonTooltipMessage: 'إزالة ${widget.values[i]}',
              ),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 96),
              child: IntrinsicWidth(
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  onSubmitted: (v) {
                    _add(v.replaceAll(_sentinel, ''));
                    _focus.requestFocus();
                  },
                  decoration: const InputDecoration.collapsed(hintText: null),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
