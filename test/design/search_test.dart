import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:delegate_app/core/design/app_theme.dart';
import 'package:delegate_app/core/design/widgets/search.dart';

List<SearchResultGroup> _search(String q, String? filter) => [
  if (filter == null || filter == 'أصناف')
    SearchResultGroup('الأصناف', [
      for (final p in ['سكر أبيض', 'سكر بني', 'زيت'])
        if (p.contains(q)) SearchResult(title: p),
    ]),
  if (filter == null || filter == 'موردين')
    SearchResultGroup('الموردين', [
      if ('شركة السكر'.contains(q)) const SearchResult(title: 'شركة السكر'),
    ]),
];

Future<List<String>> _pump(
  WidgetTester t, {
  double width = 360,
  bool icon = false,
}) async {
  t.view.physicalSize = Size(width, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final log = <String>[];
  await t.pumpWidget(
    MaterialApp(
      theme: TashilTheme.light(),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Align(
              alignment: Alignment.topCenter,
              child: TashilSearch(
                hintText: 'ابحث في الأصناف',
                recent: const ['زيت'],
                filters: const ['أصناف', 'موردين'],
                search: _search,
                asIconButton: icon,
                onSelected: (r) => log.add('selected ${r.title}'),
                onSubmitted: (q) => log.add('submitted $q'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return log;
}

SearchAnchor _anchor(WidgetTester t) => t.widget(find.byType(SearchAnchor));

void main() {
  testWidgets('compact: full screen, recent searches before typing', (t) async {
    await _pump(t);
    expect(_anchor(t).isFullScreen, isTrue);
    await t.tap(find.byType(SearchBar));
    await t.pumpAndSettle();
    expect(find.text('الأخيرة'), findsOneWidget);
    expect(find.text('زيت'), findsOneWidget);
  });

  testWidgets('medium: docked view', (t) async {
    await _pump(t, width: 800);
    expect(_anchor(t).isFullScreen, isFalse);
  });

  testWidgets('typing shows grouped results; a filter narrows them', (t) async {
    final log = await _pump(t);
    await t.tap(find.byType(SearchBar));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).last, 'سكر');
    await t.pumpAndSettle();
    expect(find.text('نتايج سريعة: 3'), findsOneWidget);
    expect(find.text('الأصناف'), findsOneWidget);
    expect(find.text('الموردين'), findsOneWidget);

    await t.tap(find.widgetWithText(FilterChip, 'موردين'));
    await t.pumpAndSettle();
    expect(find.text('نتايج سريعة: 1'), findsOneWidget);
    expect(find.text('الأصناف'), findsNothing);

    await t.tap(find.text('شركة السكر'));
    await t.pumpAndSettle();
    expect(log, ['selected شركة السكر']);
  });

  testWidgets('Enter searches, keeps the query, adds it to recent', (t) async {
    final log = await _pump(t);
    await t.tap(find.byType(SearchBar));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).last, 'أرز');
    await t.pumpAndSettle();
    expect(find.textContaining('مفيش نتايج'), findsOneWidget);
    await t.testTextInput.receiveAction(TextInputAction.search);
    await t.pumpAndSettle();
    expect(log, ['submitted أرز']);
    expect(find.text('أرز'), findsOneWidget);

    await t.tap(find.byType(SearchBar));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).last, '');
    await t.pumpAndSettle();
    expect(find.text('أرز'), findsWidgets);
    expect(find.text('زيت'), findsOneWidget);
  });

  testWidgets('icon button entry opens focused search', (t) async {
    await _pump(t, icon: true);
    expect(find.byType(SearchBar), findsNothing);
    await t.tap(find.byIcon(Icons.search));
    await t.pumpAndSettle();
    expect(find.text('الأخيرة'), findsOneWidget);
  });

  test('at most two trailing icons', () {
    expect(
      () => TashilSearch(
        hintText: 'x',
        search: _search,
        trailing: const [SizedBox(), SizedBox(), SizedBox()],
      ),
      throwsAssertionError,
    );
  });
}
