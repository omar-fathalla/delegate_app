import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:delegate_app/core/design/app_localizations.dart';
import 'package:delegate_app/core/design/app_theme.dart';
import 'package:delegate_app/core/design/widgets/dialogs.dart';

Widget _app(Widget Function(BuildContext) button) => MaterialApp(
  theme: TashilTheme.light(),
  locale: TashilLocale.arabic,
  supportedLocales: TashilLocale.supported,
  localizationsDelegates: TashilLocale.delegates,
  home: Scaffold(
    body: Center(child: Builder(builder: button)),
  ),
);

class _Form extends StatefulWidget {
  const _Form();
  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> {
  final c = TextEditingController();
  String? error;
  @override
  Widget build(BuildContext context) => FormDialog(
    title: 'صنف جديد',
    saveLabel: 'حفظ',
    dirty: c.text.isNotEmpty,
    onSave: () => setState(() => error = 'اكتب اسم الصنف'),
    child: TextField(
      controller: c,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(errorText: error),
    ),
  );
}

void main() {
  testWidgets('choice dialog: confirm disabled until a choice', (t) async {
    String? result;
    await t.pumpWidget(
      _app(
        (c) => FilledButton(
          onPressed: () async => result = await showChoiceDialog<int>(
            context: c,
            title: 'سبب المرتجع',
            confirmLabel: 'تسجيل',
            options: const {1: 'تالف', 2: 'منتهي الصلاحية'},
          ).then((v) => '$v'),
          child: const Text('open'),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    TextButton confirm() => t.widget<TextButton>(
      find.ancestor(of: find.text('تسجيل'), matching: find.byType(TextButton)),
    );
    expect(confirm().onPressed, isNull);
    await t.tap(find.text('تالف'));
    await t.pump();
    expect(confirm().onPressed, isNotNull);
    await t.tap(find.text('تسجيل'));
    await t.pumpAndSettle();
    expect(result, '1');
  });

  Future<void> openForm(WidgetTester t) async {
    await t.pumpWidget(
      _app(
        (c) => FilledButton(
          onPressed: () =>
              Navigator.of(c)
                  .push(MaterialPageRoute<void>(builder: (_) => const _Form())),
          child: const Text('open'),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
  }

  testWidgets('full-screen on compact, inline errors, discard confirm', (
    t,
  ) async {
    t.view.physicalSize = const Size(360, 780);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await openForm(t);
    expect(find.byType(Dialog), findsOneWidget); // Dialog.fullscreen
    expect(find.byType(AlertDialog), findsNothing);

    await t.tap(find.text('حفظ'));
    await t.pump();
    expect(find.text('اكتب اسم الصنف'), findsOneWidget);

    // No edits: ✕ closes straight away.
    await t.tap(find.byType(CloseButton));
    await t.pumpAndSettle();
    expect(find.byType(_Form), findsNothing);

    // With edits: ✕ asks first.
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'سكر');
    await t.pump();
    await t.tap(find.byType(CloseButton));
    await t.pumpAndSettle();
    expect(find.text('تتجاهل التعديلات؟'), findsOneWidget);
    await t.tap(find.text('كمّل تعديل'));
    await t.pumpAndSettle();
    expect(find.byType(_Form), findsOneWidget);

    // System back asks too.
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.text('تتجاهل التعديلات؟'), findsOneWidget);
    await t.tap(find.text('تجاهل'));
    await t.pumpAndSettle();
    expect(find.byType(_Form), findsNothing);
  });

  testWidgets('basic dialog from 600dp', (t) async {
    t.view.physicalSize = const Size(900, 700);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await openForm(t);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(CloseButton), findsNothing);
  });
}
