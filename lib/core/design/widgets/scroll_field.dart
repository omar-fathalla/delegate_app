import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../motion.dart';
import '../tokens.dart';

/// M3 Expressive **scroll field**
/// (m3.material.io/components/scroll-fields/guidelines).
///
/// Flutter does not ship it yet, so this arranges the official
/// [ListWheelScrollView] (snapping with [FixedExtentScrollPhysics]) and,
/// for keyboard input, a [TextField]. Replace with Flutter's once it ships.
///
/// Rules from the page:
/// * Best for picking from a list of numbers (weight, quantity, units).
///   For a time, use the time picker instead.
/// * Swipe, or tap the value above or below, to move. The centred value
///   snaps into place and is larger and darker.
/// * Always offer keyboard input: [textInput] swaps the field for a text
///   field; place the keyboard button near the fields. Strings
///   auto-complete from the first letters. Errors go under the field.
/// * Up to four digits. Long runs (5+ digits) need intervals between
///   values (e.g. grams in steps of 50) or a text field instead.
/// * Label each field when several sit side by side.
/// * Inactive values are cropped to show there is more. Corners never
///   below 16dp.
enum ScrollFieldSize {
  /// 1 or 2 digits.
  small(100),

  /// 3 digits.
  medium(144),

  /// 4 digits.
  large(186);

  const ScrollFieldSize(this.minWidth);

  /// Minimum width from the M3 sizing guidance.
  final double minWidth;
}

class ScrollField<T> extends StatefulWidget {
  const ScrollField({
    super.key,
    required this.values,
    required this.value,
    required this.onChanged,
    required this.format,
    this.parse,
    this.label,
    this.size = ScrollFieldSize.small,
    this.height = 152,
    this.width,
    this.textInput = false,
    this.enabled = true,
  });

  final List<T> values;
  final T value;
  final ValueChanged<T> onChanged;
  final String Function(T) format;

  /// For keyboard input of numbers. Without it, typed text auto-completes
  /// to the first value whose label starts with it (for strings).
  final T? Function(String)? parse;

  /// Shown above the field; required when fields sit side by side.
  final String? label;
  final ScrollFieldSize size;

  /// Taller and wider fields fit larger windows better.
  final double height;

  /// Fixed width; defaults to the size's minimum. Use
  /// `double.infinity` to fill the container.
  final double? width;

  /// Show a text field instead of the wheel (keyboard input).
  final bool textInput;
  final bool enabled;

  @override
  State<ScrollField<T>> createState() => _ScrollFieldState<T>();
}

class _ScrollFieldState<T> extends State<ScrollField<T>> {
  static const _extent = 64.0;

  late FixedExtentScrollController _wheel = FixedExtentScrollController(
    initialItem: _index,
  );
  final _text = TextEditingController();
  final _focus = FocusNode();
  final _textFocus = FocusNode();
  bool _scrolling = false;
  String? _error;

  int get _index => widget.values.indexOf(widget.value).clamp(0, 1 << 30);

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
    _textFocus.addListener(() {
      if (!_textFocus.hasFocus) _commit(_text.text, finished: true);
      setState(() {});
    });
    _syncText();
  }

  @override
  void didUpdateWidget(ScrollField<T> old) {
    super.didUpdateWidget(old);
    if (old.textInput != widget.textInput) {
      _error = null;
      _syncText();
      if (!widget.textInput) {
        _wheel.dispose();
        _wheel = FixedExtentScrollController(initialItem: _index);
      }
    } else if (old.value != widget.value &&
        !widget.textInput &&
        _wheel.hasClients &&
        _wheel.selectedItem != _index) {
      _wheel.jumpToItem(_index);
    }
  }

  void _syncText() => _text.text = widget.format(widget.value);

  @override
  void dispose() {
    _wheel.dispose();
    _text.dispose();
    _focus.dispose();
    _textFocus.dispose();
    super.dispose();
  }

  void _go(int delta) {
    final i = (_wheel.selectedItem + delta).clamp(0, widget.values.length - 1);
    _wheel.animateToItem(
      i,
      duration: TashilMotion.scaled(context, TashilMotion.fast.duration),
      curve: TashilSpring.fastEffects.curve,
    );
  }

  /// Typed text: numbers are parsed; strings auto-complete from the
  /// first letters.
  void _commit(String typed, {bool finished = false}) {
    final t = typed.trim();
    T? match;
    if (widget.parse != null) {
      final v = widget.parse!(t);
      if (v != null && widget.values.contains(v)) match = v;
    } else if (t.isNotEmpty) {
      for (final v in widget.values) {
        if (widget.format(v).startsWith(t)) {
          match = v;
          break;
        }
      }
      if (match != null && !finished && widget.format(match) != t) {
        final full = widget.format(match);
        _text.value = TextEditingValue(
          text: full,
          selection: TextSelection(
            baseOffset: t.length,
            extentOffset: full.length,
          ),
        );
      }
    }
    setState(
      () => _error = match == null && t.isNotEmpty ? 'قيمة مش موجودة' : null,
    );
    if (match != null && match != widget.value) widget.onChanged(match);
    if (finished && match != null) _syncText();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final active = text.displaySmall?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final inactive = text.headlineSmall?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final selected = _focus.hasFocus || _textFocus.hasFocus || _scrolling;
    final width = widget.width ?? widget.size.minWidth;
    final i = _index;

    Widget box(Widget child) => AnimatedContainer(
      duration: TashilMotion.scaled(context, TashilMotion.fast.duration),
      curve: TashilSpring.fastEffects.curve,
      width: width,
      height: widget.textInput ? 88 : widget.height,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(TashilRadius.large),
        border: Border.all(
          color: _error != null
              ? scheme.error
              : selected
              ? scheme.primary
              : scheme.outlineVariant,
          width: selected || _error != null ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );

    final Widget field;
    if (widget.textInput) {
      field = box(
        Center(
          child: TextField(
            controller: _text,
            focusNode: _textFocus,
            enabled: widget.enabled,
            onChanged: _commit,
            onSubmitted: (s) => _commit(s, finished: true),
            keyboardType: widget.parse != null
                ? TextInputType.number
                : TextInputType.text,
            inputFormatters: [
              if (widget.parse != null)
                FilteringTextInputFormatter.allow(RegExp('[0-9\u0660-\u0669]')),
            ],
            textAlign: TextAlign.center,
            cursorColor: scheme.primary,
            style: active?.copyWith(color: scheme.primary),
            decoration: InputDecoration.collapsed(
              hintText: widget.format(widget.value),
            ).copyWith(semanticCounterText: widget.label),
          ),
        ),
      );
    } else {
      field = Semantics(
        label: widget.label,
        value: widget.format(widget.value),
        increasedValue: i + 1 < widget.values.length
            ? widget.format(widget.values[i + 1])
            : null,
        decreasedValue: i > 0 ? widget.format(widget.values[i - 1]) : null,
        onIncrease: i + 1 < widget.values.length ? () => _go(1) : null,
        onDecrease: i > 0 ? () => _go(-1) : null,
        excludeSemantics: true,
        child: Focus(
          focusNode: _focus,
          canRequestFocus: widget.enabled,
          onKeyEvent: (_, e) {
            if (e is KeyUpEvent) return KeyEventResult.ignored;
            if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
              _go(-1);
              return KeyEventResult.handled;
            }
            if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
              _go(1);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n is ScrollStartNotification && n.dragDetails != null) {
                setState(() => _scrolling = true);
              } else if (n is ScrollEndNotification && _scrolling) {
                setState(() => _scrolling = false);
              }
              return false;
            },
            child: box(
              ListWheelScrollView.useDelegate(
                controller: _wheel,
                itemExtent: _extent,
                diameterRatio: 3,
                physics: widget.enabled
                    ? const FixedExtentScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
                onSelectedItemChanged: (n) {
                  if (widget.values[n] != widget.value) {
                    HapticFeedback.selectionClick();
                    widget.onChanged(widget.values[n]);
                  }
                },
                childDelegate: ListWheelChildBuilderDelegate(
                  childCount: widget.values.length,
                  builder: (context, n) {
                    final isActive = n == i;
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.enabled
                          ? () {
                              _focus.requestFocus();
                              _go(n - _wheel.selectedItem);
                            }
                          : null,
                      child: Center(
                        child: AnimatedDefaultTextStyle(
                          duration: TashilMotion.scaled(
                            context,
                            TashilMotion.fast.duration,
                          ),
                          curve: TashilSpring.fastEffects.curve,
                          style: (isActive ? active : inactive)!.copyWith(
                            color: !widget.enabled
                                ? scheme.onSurface.withValues(alpha: 0.38)
                                : isActive
                                ? (selected ? scheme.primary : scheme.onSurface)
                                : scheme.outline,
                          ),
                          child: Text(
                            widget.format(widget.values[n]),
                            maxLines: 1,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (widget.label != null) ...[
          Text(
            widget.label!,
            style: text.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: TashilSpacing.xs),
        ],
        field,
        if (_error != null) ...[
          const SizedBox(height: TashilSpacing.xs),
          SizedBox(
            width: width,
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(color: scheme.error),
            ),
          ),
        ],
      ],
    );
  }
}

/// The button that swaps scroll fields to keyboard input and back. Place
/// it next to the fields it controls.
class ScrollFieldInputToggle extends StatelessWidget {
  const ScrollFieldInputToggle({
    super.key,
    required this.textInput,
    required this.onChanged,
  });

  final bool textInput;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: textInput ? 'اختيار بالتمرير' : 'إدخال بالكيبورد',
    isSelected: textInput,
    icon: const Icon(Icons.keyboard_outlined),
    selectedIcon: const Icon(Icons.swipe_vertical_outlined),
    onPressed: () => onChanged(!textInput),
  );
}

/// Reads a whole number typed by a person; Arabic-Indic digits (٠-٩) are
/// read as 0-9. Use as [ScrollField.parse] for numbers.
int? parseTypedInt(String input) => int.tryParse(
  input
      .replaceAllMapped(
        RegExp('[٠-٩]'),
        (m) => '${m[0]!.codeUnitAt(0) - 0x0660}',
      )
      .trim(),
);
