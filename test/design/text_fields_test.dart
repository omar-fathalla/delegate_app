import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:delegate_app/core/design/app_theme.dart';
import 'package:delegate_app/core/design/widgets/text_fields.dart';

Future<void> _app(WidgetTester t, Widget child, {double width = 360}) async {
  t.view.physicalSize = Size(width, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: TashilTheme.light(),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('error replaces supporting text and shows an error icon', (
    t,
  ) async {
    await _app(
      t,
      const TashilTextField(
        label: 'الباركود',
        supportingText: 'امسحه بالكاميرا',
        errorText: 'الباركود 13 رقم',
        trailing: Icon(Icons.qr_code_scanner),
      ),
    );
    expect(find.text('الباركود 13 رقم'), findsOneWidget);
    expect(find.text('امسحه بالكاميرا'), findsNothing);
    expect(find.byIcon(Icons.error), findsOneWidget);
    expect(find.byIcon(Icons.qr_code_scanner), findsNothing);
  });

  testWidgets('valid icon when valid', (t) async {
    await _app(t, const TashilTextField(label: 'الباركود', valid: true));
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('clear icon only while there is text, and it clears', (t) async {
    await _app(t, const TashilTextField(label: 'اسم الصنف', clearable: true));
    expect(find.byIcon(Icons.cancel_outlined), findsNothing);
    await t.enterText(find.byType(TextField), 'سكر');
    await t.pump();
    expect(find.byIcon(Icons.cancel_outlined), findsOneWidget);
    await t.tap(find.byIcon(Icons.cancel_outlined));
    await t.pump();
    expect(find.text('سكر'), findsNothing);
    expect(find.byIcon(Icons.cancel_outlined), findsNothing);
  });

  testWidgets('required: asterisk, read as required; note explains it', (
    t,
  ) async {
    final s = t.ensureSemantics();
    await _app(
      t,
      const Column(
        children: [
          RequiredFieldsNote(),
          TashilTextField(label: 'اسم الصنف', isRequired: true),
        ],
      ),
    );
    expect(find.text('اسم الصنف *'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('اسم الصنف، مطلوب')), findsOneWidget);
    expect(find.textContaining('العلامة *'), findsOneWidget);
    s.dispose();
  });

  testWidgets('character counter with a limit', (t) async {
    await _app(t, const TashilTextField(label: 'الاسم', maxLength: 40));
    await t.enterText(find.byType(TextField), 'سكر');
    await t.pump();
    expect(find.text('3/40'), findsOneWidget);
  });

  testWidgets('multi-line grows, text area has a fixed height', (t) async {
    await _app(
      t,
      const TashilTextField(label: 'ملاحظات', lines: TextFieldLines.multi),
    );
    final one = t.getSize(find.byType(TextField)).height;
    await t.enterText(find.byType(TextField), 'سطر\nسطر\nسطر');
    await t.pump();
    expect(t.getSize(find.byType(TextField)).height, greaterThan(one));

    await _app(
      t,
      const TashilTextField(label: 'سبب', lines: TextFieldLines.area),
    );
    final area = t.getSize(find.byType(TextField)).height;
    expect(area, greaterThan(one));
    await t.enterText(
      find.byType(TextField),
      List.filled(10, 'سطر').join('\n'),
    );
    await t.pump();
    expect(t.getSize(find.byType(TextField)).height, area);
  });

  testWidgets('read-only looks normal and says so', (t) async {
    await _app(t, const TashilTextField(label: 'رقم الفاتورة', readOnly: true));
    final f = t.widget<TextField>(find.byType(TextField));
    expect(f.readOnly, isTrue);
    expect(f.enabled, isTrue);
    expect(find.textContaining('للقراءة بس'), findsOneWidget);
  });

  testWidgets('form column: full width on compact, capped on wide', (t) async {
    const form = FormColumn(children: [TashilTextField(label: 'الاسم')]);
    await _app(t, form);
    expect(t.getSize(find.byType(TextField)).width, 360 - 32);
    await _app(t, form, width: 1200);
    final r = t.getRect(find.byType(TextField));
    expect(r.width, 560);
    expect(r.right, closeTo(1200 - 16, 0.5), reason: 'start edge in RTL');
  });
}
