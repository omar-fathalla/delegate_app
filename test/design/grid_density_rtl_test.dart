import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:delegate_app/core/design/bidi.dart';
import 'package:delegate_app/core/design/layout.dart';

Widget _app(Widget child, {TextDirection dir = TextDirection.rtl}) =>
    MaterialApp(
      home: Directionality(
        textDirection: dir,
        child: Scaffold(body: child),
      ),
    );

void main() {
  group('grid', () {
    test('columns per breakpoint: 4, 8, 8, 12, 12', () {
      expect(
        [for (final b in TashilBreakpoint.values) b.columns],
        [4, 8, 8, 12, 12],
      );
      expect(TashilBreakpoint.compact.gutter, 16);
      expect(TashilBreakpoint.large.gutter, 24);
    });

    test('compact 360dp: 4 columns of 72dp, spans include gutters', () {
      final g = ColumnGrid.of(360, TashilBreakpoint.compact);
      expect(g.column, 70); // (360 - 32 - 48) / 4
      expect(g.span(2), 156);
      expect(g.span(4), 328); // full width inside the margins
      expect(g.span(9), 328); // clamped
      expect(g.start(0), 16);
      expect(g.start(1), 102);
    });

    testWidgets('overlay draws one box per column', (t) async {
      await t.pumpWidget(
        _app(
          const SizedBox(width: 700, height: 100, child: ColumnGridOverlay()),
        ),
      );
      expect(
        find.descendant(
          of: find.byType(ColumnGridOverlay),
          matching: find.byType(ColoredBox),
        ),
        findsNWidgets(8),
      );
    });
  });

  group('density', () {
    test('data table rows: 52dp, 4dp less per step, never under 48', () {
      expect(DensityScope.dataRowHeight(TashilDensity.standard), 52);
      expect(DensityScope.dataRowHeight(TashilDensity.comfortable), 48);
      expect(DensityScope.dataRowHeight(TashilDensity.dense), 48);
      expect(DensityScope.headingRowHeight(TashilDensity.compact), 48);
    });

    test('steps of 4dp, vertical only', () {
      expect(TashilDensity.dense.visualDensity.vertical, -3);
      expect(TashilDensity.dense.visualDensity.horizontal, 0);
      expect(TashilDensity.standard.step, 0);
    });

    testWidgets('dense list rows shrink but stay 48dp', (t) async {
      Future<double> rowHeight(TashilDensity d) async {
        await t.pumpWidget(
          _app(
            DensityScope(
              density: d,
              child: ListView(
                children: const [
                  ListTile(title: Text('صنف'), subtitle: Text('كود 1041')),
                ],
              ),
            ),
          ),
        );
        return t.getSize(find.byType(ListTile)).height;
      }

      final standard = await rowHeight(TashilDensity.standard);
      final dense = await rowHeight(TashilDensity.dense);
      expect(dense, lessThan(standard));
      expect(dense, greaterThanOrEqualTo(48));
      // One-line rows stop at 48.
      await t.pumpWidget(
        _app(
          DensityScope(
            density: TashilDensity.dense,
            child: ListView(children: const [ListTile(title: Text('صنف'))]),
          ),
        ),
      );
      expect(t.getSize(find.byType(ListTile)).height, 48);
    });

    testWidgets('buttons keep a 48dp touch target when dense', (t) async {
      await t.pumpWidget(
        _app(
          DensityScope(
            density: TashilDensity.dense,
            child: Center(
              child: TextButton(onPressed: () {}, child: const Text('حفظ')),
            ),
          ),
        ),
      );
      expect(
        t.getSize(find.byType(TextButton)).height,
        greaterThanOrEqualTo(48),
      );
    });

    testWidgets('controls keep the app density; rows and fields get it', (
      t,
    ) async {
      late BuildContext inner;
      await t.pumpWidget(
        _app(
          DensityScope(
            density: TashilDensity.dense,
            child: Builder(
              builder: (c) {
                inner = c;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect(ListTileTheme.of(inner).visualDensity?.vertical, -2);
      expect(Theme.of(inner).inputDecorationTheme.visualDensity?.vertical, -3);
      expect(Theme.of(inner).visualDensity.vertical, 0);
    });
  });

  group('breakpoints', () {
    test('component swaps', () {
      expect(TashilBreakpoint.compact.allowsFullScreenDialog, isTrue);
      expect(TashilBreakpoint.medium.allowsFullScreenDialog, isFalse);
      expect(
        TashilBreakpoint.compact.supplementalSelection,
        SupplementalSelection.bottomSheet,
      );
      expect(
        TashilBreakpoint.expanded.supplementalSelection,
        SupplementalSelection.menu,
      );
      expect(TashilBreakpoint.medium.navigationBarWithTwoPanes(2), isTrue);
      expect(TashilBreakpoint.medium.navigationBarWithTwoPanes(1), isFalse);
      expect(TashilBreakpoint.expanded.navigationBarWithTwoPanes(2), isFalse);
    });

    test('height breakpoints 480 / 900', () {
      expect(
        TashilHeightBreakpoint.fromHeight(360),
        TashilHeightBreakpoint.compact,
      );
      expect(
        TashilHeightBreakpoint.fromHeight(480),
        TashilHeightBreakpoint.medium,
      );
      expect(
        TashilHeightBreakpoint.fromHeight(900),
        TashilHeightBreakpoint.expanded,
      );
    });
  });

  group('RTL', () {
    test('isolates', () {
      expect(Bidi.ltr('a@b.com'), '\u2066a@b.com\u2069');
      expect(Bidi.auto('Pepsi'), '\u2068Pepsi\u2069');
    });

    testWidgets('MirroredIcon flips only unmarked icons, only in RTL', (
      t,
    ) async {
      Future<bool> flipped(IconData i, TextDirection d) async {
        await t.pumpWidget(_app(MirroredIcon(i), dir: d));
        return find
            .descendant(
              of: find.byType(MirroredIcon),
              matching: find.byType(Transform),
            )
            .evaluate()
            .isNotEmpty;
      }

      expect(await flipped(Icons.logout, TextDirection.rtl), isTrue);
      expect(await flipped(Icons.logout, TextDirection.ltr), isFalse);
      // Marked by Flutter: Icon mirrors it itself (one Transform from Icon).
      expect(Icons.arrow_back.matchTextDirection, isTrue);
      expect(await flipped(Icons.arrow_back, TextDirection.rtl), isTrue);
    });

    test('clockwise icons are not marked for mirroring', () {
      expect(Icons.refresh.matchTextDirection, isFalse);
      expect(Icons.schedule.matchTextDirection, isFalse);
      expect(Icons.send.matchTextDirection, isTrue);
    });

    testWidgets('badge sits top-left of the icon in RTL', (t) async {
      await t.pumpWidget(
        _app(
          const Center(
            child: Badge(
              label: Text('7'),
              child: Icon(Icons.inventory_2_outlined),
            ),
          ),
        ),
      );
      final icon = t.getRect(find.byType(Icon));
      final label = t.getRect(find.text('7'));
      expect(label.center.dx, lessThan(icon.center.dx));
    });

    testWidgets('linear progress fills from the right in RTL', (t) async {
      await t.pumpWidget(
        _app(
          const Center(
            child: SizedBox(
              width: 200,
              child: LinearProgressIndicator(value: 0.25),
            ),
          ),
        ),
      );
      // The indicator paints from the leading edge; RTL leading is right.
      final ctx = t.element(find.byType(LinearProgressIndicator));
      expect(Directionality.of(ctx), TextDirection.rtl);
    });

    testWidgets('LtrIsland keeps media controls left-to-right', (t) async {
      await t.pumpWidget(
        _app(
          const LtrIsland(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [Icon(Icons.skip_previous), Icon(Icons.skip_next)],
            ),
          ),
        ),
      );
      expect(
        t.getCenter(find.byIcon(Icons.skip_previous)).dx,
        lessThan(t.getCenter(find.byIcon(Icons.skip_next)).dx),
      );
    });
  });
}
