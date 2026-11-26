import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../motion.dart';
import '../tokens.dart';

/// Date entry for forms (m3.material.io/components/date-pickers/guidelines).
///
/// A text field that takes the date from the keyboard, plus a calendar
/// button. Built only from official Flutter parts:
///
/// * parsing and formatting with [MaterialLocalizations] (same format as the
///   official date picker's input mode);
/// * compact screens (SUNMI V3): the calendar button opens the official
///   modal [showDatePicker] in calendar-only mode (typing happens in the
///   field, see [parseTypedDate]);
/// * medium and expanded screens (>= 600dp): the calendar drops down under
///   the field (M3 "docked date picker"), using the official
///   [CalendarDatePicker].
class DateField extends StatefulWidget {
  const DateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.firstDate,
    required this.lastDate,
    this.docked,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final DateTime firstDate;
  final DateTime lastDate;

  /// Force docked (true) or modal (false). Null: docked from 600dp wide.
  final bool? docked;

  @override
  State<DateField> createState() => _DateFieldState();
}

class _DateFieldState extends State<DateField> {
  final _text = TextEditingController();
  final _menu = MenuController();
  String? _error;
  DateTime? _draft;
  DateTime? _shown;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(DateField old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  /// Show [DateField.value] in the field when it changed from outside.
  void _sync() {
    if (widget.value == _shown) return;
    _shown = widget.value;
    final v = widget.value;
    _text.text = v == null
        ? ''
        : MaterialLocalizations.of(context).formatCompactDate(v);
    _error = null;
  }

  bool _inRange(DateTime d) =>
      !d.isBefore(widget.firstDate) && !d.isAfter(widget.lastDate);

  void _typed(String s) {
    final loc = MaterialLocalizations.of(context);
    if (s.trim().isEmpty) {
      setState(() => _error = null);
      _emit(null);
      return;
    }
    final d = parseTypedDate(s, loc);
    setState(() {
      _error = d == null
          ? loc.invalidDateFormatLabel
          : !_inRange(d)
          ? loc.dateOutOfRangeLabel
          : null;
    });
    if (_error == null) _emit(d);
  }

  void _emit(DateTime? d) {
    _shown = d;
    widget.onChanged(d);
  }

  void _picked(DateTime d) {
    _text.text = MaterialLocalizations.of(context).formatCompactDate(d);
    setState(() => _error = null);
    _emit(d);
  }

  DateTime get _initial {
    final v = widget.value ?? DateTime.now();
    if (v.isBefore(widget.firstDate)) return widget.firstDate;
    if (v.isAfter(widget.lastDate)) return widget.lastDate;
    return v;
  }

  Future<void> _openModal() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _initial,
      firstDate: widget.firstDate,
      lastDate: widget.lastDate,
      // The field itself is the keyboard entry. The dialog's own input
      // mode rejects "15/4/2027" in Arabic (it expects hidden RTL marks).
      initialEntryMode: DatePickerEntryMode.calendarOnly,
    );
    if (d != null) _picked(d);
  }

  @override
  Widget build(BuildContext context) {
    final loc = MaterialLocalizations.of(context);
    final docked =
        widget.docked ??
        MediaQuery.sizeOf(context).width >= TashilSizes.compactMax;

    final field = TextField(
      controller: _text,
      keyboardType: TextInputType.datetime,
      onChanged: _typed,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: loc.dateHelpText,
        helperText: loc.dateHelpText,
        errorText: _error,
        suffixIcon: IconButton(
          tooltip: loc.datePickerHelpText,
          icon: const Icon(Icons.calendar_today_outlined),
          onPressed: docked
              ? () {
                  _draft = _initial;
                  _menu.isOpen ? _menu.close() : _menu.open();
                }
              : _openModal,
        ),
      ),
    );
    if (!docked) return field;

    return MenuAnchor(
      controller: _menu,
      style: const MenuStyle(padding: WidgetStatePropertyAll(EdgeInsets.zero)),
      menuChildren: [
        // The menu has its own scroll view; keep the calendar's grid off
        // the primary controller so the two don't share one.
        PrimaryScrollController.none(
          child: SizedBox(
            width: 328,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CalendarDatePicker(
                  initialDate: _initial,
                  firstDate: widget.firstDate,
                  lastDate: widget.lastDate,
                  onDateChanged: (d) => _draft = d,
                ),
                Padding(
                  padding: const EdgeInsets.all(TashilSpacing.sm),
                  child: OverflowBar(
                    alignment: MainAxisAlignment.end,
                    spacing: TashilSpacing.sm,
                    children: [
                      TextButton(
                        onPressed: _menu.close,
                        child: Text(loc.cancelButtonLabel),
                      ),
                      TextButton(
                        onPressed: () {
                          _menu.close();
                          if (_draft != null) _picked(_draft!);
                        },
                        child: Text(loc.okButtonLabel),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
      child: field,
    );
  }
}

/// Parses a date typed by a person, more forgiving than
/// [MaterialLocalizations.parseCompactDate]:
///
/// * the Arabic compact format carries invisible right-to-left marks
///   (`9\u200F/3\u200F/2027`); nobody types those, so they are optional;
/// * Arabic-Indic digits (٠-٩) are accepted and read as 0-9;
/// * `/`, `-` and `.` all work as separators, day first (Egypt).
DateTime? parseTypedDate(String input, MaterialLocalizations loc) {
  final s = input
      .replaceAll(RegExp('[\u200E\u200F\u061C]'), '')
      .replaceAllMapped(
        RegExp('[\u0660-\u0669]'),
        (m) => '${m[0]!.codeUnitAt(0) - 0x0660}',
      )
      .trim();
  final official = loc.parseCompactDate(s);
  if (official != null) return official;
  final m = RegExp(r'^(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{4})$').firstMatch(s);
  if (m == null) return null;
  final day = int.parse(m[1]!);
  final month = int.parse(m[2]!);
  final year = int.parse(m[3]!);
  final d = DateTime(year, month, day);
  // Reject 31/2 rolling over into March.
  return d.day == day && d.month == month ? d : null;
}

/// M3 Expressive **scroll time picker**
/// (m3.material.io/components/time-pickers/guidelines). Flutter ships only
/// the dial and input pickers (as dialogs), so this one is ours, built on
/// the official [ListWheelScrollView]. Replace with Flutter's when it ships.
///
/// * Inline, so the rest of the form stays visible (M3: prefer inline).
/// * Swipe a field to change it; values snap. Tap the value above or below
///   to move to it.
/// * The keyboard button switches to input mode, and back (M3: the toggle
///   must always be there).
/// * 12 or 24 hours follows the device setting; 24h hides AM/PM.
/// * Digits are always Western; hh:mm stays left-to-right in Arabic.
class ScrollTimePicker extends StatefulWidget {
  const ScrollTimePicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.use24HourFormat,
  });

  final TimeOfDay value;
  final ValueChanged<TimeOfDay> onChanged;

  /// Null: follow the device (`MediaQuery.alwaysUse24HourFormat`).
  final bool? use24HourFormat;

  @override
  State<ScrollTimePicker> createState() => _ScrollTimePickerState();
}

class _ScrollTimePickerState extends State<ScrollTimePicker> {
  static const _extent = 64.0;
  static const _fieldWidth = 96.0;
  static const _fieldHeight = 152.0;

  bool _input = false;
  late FixedExtentScrollController _hours;
  late FixedExtentScrollController _minutes;
  final _hourText = TextEditingController();
  final _minuteText = TextEditingController();
  final _minuteFocus = FocusNode();
  bool? _built24;

  bool get _is24 =>
      widget.use24HourFormat ?? MediaQuery.alwaysUse24HourFormatOf(context);

  int _hourIndex(TimeOfDay t) =>
      _is24 ? t.hour : (t.hourOfPeriod == 0 ? 11 : t.hourOfPeriod - 1);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_built24 != _is24) {
      if (_built24 != null) {
        _hours.dispose();
        _minutes.dispose();
      }
      _makeControllers();
    }
  }

  void _makeControllers() {
    _built24 = _is24;
    _hours = FixedExtentScrollController(initialItem: _hourIndex(widget.value));
    _minutes = FixedExtentScrollController(initialItem: widget.value.minute);
  }

  @override
  void dispose() {
    _hours.dispose();
    _minutes.dispose();
    _hourText.dispose();
    _minuteText.dispose();
    _minuteFocus.dispose();
    super.dispose();
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  int _displayHour(TimeOfDay t) =>
      _is24 ? t.hour : (t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod);

  void _emitHour(int index) {
    final i = index % (_is24 ? 24 : 12);
    final h = _is24
        ? i
        : (i + 1) % 12 + (widget.value.period == DayPeriod.pm ? 12 : 0);
    _emit(widget.value.replacing(hour: h));
  }

  void _emit(TimeOfDay t) {
    if (t == widget.value) return;
    HapticFeedback.selectionClick();
    widget.onChanged(t);
  }

  void _setPeriod(DayPeriod p) {
    if (p == widget.value.period) return;
    final h = widget.value.hourOfPeriod + (p == DayPeriod.pm ? 12 : 0);
    _emit(widget.value.replacing(hour: h));
  }

  void _toggleMode() {
    setState(() {
      _input = !_input;
      if (_input) {
        _hourText.text = _two(_displayHour(widget.value));
        _minuteText.text = _two(widget.value.minute);
      } else {
        _hours.dispose();
        _minutes.dispose();
        _makeControllers();
      }
    });
  }

  void _typedHour(String s) {
    final n = int.tryParse(s);
    if (n == null) return;
    final ok = _is24 ? n <= 23 : (n >= 1 && n <= 12);
    if (!ok) return;
    final h = _is24
        ? n
        : n % 12 + (widget.value.period == DayPeriod.pm ? 12 : 0);
    _emit(widget.value.replacing(hour: h));
    if (s.length == 2) _minuteFocus.requestFocus();
  }

  void _typedMinute(String s) {
    final n = int.tryParse(s);
    if (n != null && n <= 59) _emit(widget.value.replacing(minute: n));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final loc = MaterialLocalizations.of(context);
    final digits = text.displayMedium?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    Widget box(Widget child) => Container(
      width: _fieldWidth,
      height: _input ? 80 : _fieldHeight,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(TashilRadius.large),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );

    Widget wheel({
      required FixedExtentScrollController controller,
      required int count,
      required String Function(int) label,
      required int selected,
      required ValueChanged<int> onSelected,
      required String semanticsLabel,
    }) {
      void go(int delta) => controller.animateToItem(
        controller.selectedItem + delta,
        duration: TashilMotion.scaled(context, TashilMotion.fast.duration),
        curve: TashilSpring.fastEffects.curve,
      );
      return Semantics(
        label: semanticsLabel,
        value: label(selected),
        increasedValue: label((selected + 1) % count),
        decreasedValue: label((selected - 1 + count) % count),
        onIncrease: () => go(1),
        onDecrease: () => go(-1),
        excludeSemantics: true,
        child: box(
          ListWheelScrollView.useDelegate(
            controller: controller,
            itemExtent: _extent,
            diameterRatio: 3,
            physics: const FixedExtentScrollPhysics(),
            onSelectedItemChanged: onSelected,
            childDelegate: ListWheelChildLoopingListDelegate(
              children: [
                for (var i = 0; i < count; i++)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      final cur = controller.selectedItem;
                      final d = ((i - cur % count) + count) % count;
                      go(d > count / 2 ? d - count : d);
                    },
                    child: Center(
                      child: Text(
                        label(i),
                        style: digits?.copyWith(
                          color: i == selected
                              ? scheme.onSurface
                              : scheme.onSurfaceVariant.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    Widget field(
      TextEditingController c,
      ValueChanged<String> onChanged,
      String semanticsLabel, {
      FocusNode? focus,
    }) => box(
      Center(
        child: TextField(
          controller: c,
          focusNode: focus,
          onChanged: onChanged,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(2),
          ],
          textAlign: TextAlign.center,
          style: digits,
          decoration: InputDecoration.collapsed(hintText: '00')
              .copyWith(semanticCounterText: semanticsLabel),
        ),
      ),
    );

    final hourCount = _is24 ? 24 : 12;
    final hours = _input
        ? field(_hourText, _typedHour, loc.timePickerHourLabel)
        : wheel(
            controller: _hours,
            count: hourCount,
            label: (i) => _two(_is24 ? i : i + 1),
            selected: _hourIndex(widget.value),
            onSelected: _emitHour,
            semanticsLabel: loc.timePickerHourLabel,
          );
    final minutes = _input
        ? field(
            _minuteText,
            _typedMinute,
            loc.timePickerMinuteLabel,
            focus: _minuteFocus,
          )
        : wheel(
            controller: _minutes,
            count: 60,
            label: _two,
            selected: widget.value.minute,
            onSelected: (i) => _emit(widget.value.replacing(minute: i % 60)),
            semanticsLabel: loc.timePickerMinuteLabel,
          );

    Widget period(DayPeriod p, String label) {
      final on = widget.value.period == p;
      return Semantics(
        selected: on,
        button: true,
        child: Material(
          color: on ? scheme.tertiaryContainer : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(TashilRadius.medium),
            side: on ? BorderSide.none : BorderSide(color: scheme.outline),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _setPeriod(p),
            child: SizedBox(
              width: 52,
              height: 48,
              child: Center(
                child: Text(
                  label,
                  style: text.titleMedium?.copyWith(
                    color: on
                        ? scheme.onTertiaryContainer
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    // hh:mm reads left to right in Arabic too (as on the official picker).
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          hours,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: TashilSpacing.xs),
            child: Text(':', style: digits),
          ),
          minutes,
          const SizedBox(width: TashilSpacing.md),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!_is24) ...[
                period(DayPeriod.am, loc.anteMeridiemAbbreviation),
                const SizedBox(height: TashilSpacing.xs),
                period(DayPeriod.pm, loc.postMeridiemAbbreviation),
              ],
              IconButton(
                tooltip: _input
                    ? loc.timePickerDialHelpText
                    : loc.timePickerInputHelpText,
                onPressed: _toggleMode,
                icon: Icon(
                  _input
                      ? Icons.swipe_vertical_outlined
                      : Icons.keyboard_outlined,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
