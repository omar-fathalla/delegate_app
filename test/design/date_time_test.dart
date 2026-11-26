import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:delegate_app/core/design/app_localizations.dart';
import 'package:delegate_app/core/design/app_theme.dart';
import 'package:delegate_app/core/design/widgets/date_time_fields.dart';

Widget _app(Widget child, {bool top = false}) => MaterialApp(
  theme: TashilTheme.light(),
  locale: TashilLocale.arabic,
  supportedLocales: TashilLocale.supported,
  localizationsDelegates: TashilLocale.delegates,
  home: Scaffold(
    body: Align(
      alignment: top ? Alignment.topCenter : Alignment.center,
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  ),
);

void main() {
  testWidgets('official date picker uses Western digits in Arabic', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (c) => FilledButton(
            onPressed: () => showDatePicker(
              context: c,
              firstDate: DateTime(2024),
              lastDate: DateTime(2030),
              initialDate: DateTime(2026, 11, 26),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('26'), findsOneWidget);
    expect(find.text('٢٦'), findsNothing);
    expect(find.textContaining('اختيار التاريخ'), findsOneWidget);
  });

  testWidgets('DateField parses typed dates and rejects bad ones', (
    tester,
  ) async {
    DateTime? value;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (c, set) => DateField(
            label: 'تاريخ',
            value: value,
            docked: false,
            firstDate: DateTime(2024),
            lastDate: DateTime(2030, 12, 31),
            onChanged: (d) => set(() => value = d),
          ),
        ),
      ),
    );
    final loc = MaterialLocalizations.of(
      tester.element(find.byType(DateField)),
    );
    final typed = loc.formatCompactDate(DateTime(2027, 3, 9));
    expect(typed, isNot(contains('٩')), reason: 'Western digits');

    await tester.enterText(find.byType(TextField), typed);
    await tester.pump();
    expect(value, DateTime(2027, 3, 9));

    // What a cashier types: day/month/year, no direction marks.
    await tester.enterText(find.byType(TextField), '15/4/2027');
    await tester.pump();
    expect(value, DateTime(2027, 4, 15));
    expect(parseTypedDate('٥/٦/٢٠٢٧', loc), DateTime(2027, 6, 5));
    expect(parseTypedDate('31/2/2027', loc), isNull);

    await tester.enterText(find.byType(TextField), '2027/13/40');
    await tester.pump();
    expect(find.text(loc.invalidDateFormatLabel), findsOneWidget);

    await tester.enterText(find.byType(TextField), '1/1/2040');
    await tester.pump();
    expect(find.text(loc.dateOutOfRangeLabel), findsOneWidget);
  });

  testWidgets('docked DateField drops the calendar under the field', (
    tester,
  ) async {
    DateTime? value = DateTime(2026, 11, 26);
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (c, set) => DateField(
            label: 'تاريخ',
            value: value,
            docked: true,
            firstDate: DateTime(2024),
            lastDate: DateTime(2030, 12, 31),
            onChanged: (d) => set(() => value = d),
          ),
        ),
        top: true,
      ),
    );
    await tester.tap(find.byIcon(Icons.calendar_today_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(CalendarDatePicker), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(
      tester.getTopLeft(find.byType(CalendarDatePicker)).dy,
      greaterThan(tester.getBottomLeft(find.byType(TextField)).dy - 30),
    );

    await tester.tap(find.text('15'));
    await tester.pump();
    await tester.tap(find.text('حسنًا'));
    await tester.pumpAndSettle();
    expect(value, DateTime(2026, 11, 15));
    expect(find.byType(CalendarDatePicker), findsNothing);
  });

  testWidgets('ScrollTimePicker: AM/PM, keyboard toggle, 24h', (tester) async {
    var value = const TimeOfDay(hour: 23, minute: 0);
    var use24 = false;
    late StateSetter setOuter;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (c, set) {
            setOuter = set;
            return ScrollTimePicker(
              value: value,
              use24HourFormat: use24,
              onChanged: (t) => set(() => value = t),
            );
          },
        ),
      ),
    );
    expect(find.text('11'), findsWidgets);

    // Period: PM -> AM keeps the hour of period.
    await tester.tap(find.text('ص'));
    await tester.pump();
    expect(value, const TimeOfDay(hour: 11, minute: 0));

    // Tap the value under the selected one (12) to move to it.
    final hourWheel = find.byType(ListWheelScrollView).first;
    await tester.tap(
      find.descendant(of: hourWheel, matching: find.text('12')).first,
    );
    await tester.pumpAndSettle();
    expect(value, const TimeOfDay(hour: 0, minute: 0), reason: '12 AM');

    // Keyboard toggle is always there; type the time.
    await tester.tap(find.byIcon(Icons.keyboard_outlined));
    await tester.pump();
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));
    await tester.enterText(fields.first, '07');
    await tester.enterText(fields.last, '45');
    await tester.pump();
    expect(value, const TimeOfDay(hour: 7, minute: 45));
    expect(find.byIcon(Icons.swipe_vertical_outlined), findsOneWidget);

    // 24h: no AM/PM.
    setOuter(() => use24 = true);
    await tester.pump();
    expect(find.text('ص'), findsNothing);
    expect(find.text('م'), findsNothing);
  });
}
