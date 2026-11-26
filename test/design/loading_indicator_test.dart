import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:delegate_app/core/design/app_theme.dart';
import 'package:delegate_app/core/design/widgets/loading_indicator.dart';

Widget _app(Widget child, {bool reduceMotion = false}) => MaterialApp(
  theme: TashilTheme.light(),
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduceMotion),
    child: Scaffold(body: Center(child: child)),
  ),
);

ShapeBorder _shape(WidgetTester t) {
  final boxes = t.widgetList<DecoratedBox>(
    find.descendant(
      of: find.byType(LoadingIndicator),
      matching: find.byType(DecoratedBox),
    ),
  );
  return (boxes.last.decoration as ShapeDecoration).shape;
}

void main() {
  testWidgets('nothing under 200ms, then the loading indicator', (t) async {
    await t.pumpWidget(_app(const DelayedLoadingIndicator()));
    expect(find.byType(LoadingIndicator), findsNothing);
    await t.pump(const Duration(milliseconds: 150));
    expect(find.byType(LoadingIndicator), findsNothing);
    await t.pump(const Duration(milliseconds: 100));
    expect(find.byType(LoadingIndicator), findsOneWidget);
    expect(find.bySemanticsLabel('جاري التحميل'), findsOneWidget);
  });

  testWidgets('morphs between Material shapes over time', (t) async {
    await t.pumpWidget(_app(const LoadingIndicator()));
    await t.pump(const Duration(milliseconds: 100));
    final a = _shape(t);
    await t.pump(const Duration(milliseconds: 700));
    final b = _shape(t);
    expect(a, isNot(equals(b)));
    expect(t.getSize(find.byType(LoadingIndicator)), const Size(48, 48));
  });

  testWidgets('reduced motion: no morphing', (t) async {
    await t.pumpWidget(_app(const LoadingIndicator(), reduceMotion: true));
    await t.pump(const Duration(milliseconds: 100));
    final a = _shape(t);
    await t.pump(const Duration(milliseconds: 1400));
    expect(_shape(t), equals(a));
  });

  testWidgets('contained sits on a primaryContainer circle', (t) async {
    await t.pumpWidget(_app(const LoadingIndicator(contained: true)));
    final theme = TashilTheme.light().colorScheme;
    final outer = t
        .widgetList<DecoratedBox>(
          find.descendant(
            of: find.byType(LoadingIndicator),
            matching: find.byType(DecoratedBox),
          ),
        )
        .first;
    final d = outer.decoration as ShapeDecoration;
    expect(d.color, theme.primaryContainer);
    expect(d.shape, isA<CircleBorder>());
  });
}
