import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:delegate_app/core/design/app_theme.dart';
import 'package:delegate_app/core/design/tokens.dart';
import 'package:delegate_app/features/playground/sample_widgets.dart';

/// Inset dividers must start exactly where the row's text starts, in both
/// directions (m3.material.io/components/divider/guidelines).
void main() {
  for (final dir in TextDirection.values) {
    Future<void> check(
      WidgetTester t,
      Widget row,
      double indent,
      Finder text,
    ) async {
      await t.pumpWidget(
        MaterialApp(
          theme: TashilTheme.light(),
          home: Directionality(
            textDirection: dir,
            child: Scaffold(
              body: Column(
                children: [
                  row,
                  Divider(indent: indent, endIndent: TashilDividerInset.both),
                ],
              ),
            ),
          ),
        ),
      );
      // Divider's indent is directional (start side), so the text must
      // begin exactly `indent` from the start edge.
      final width = t.getSize(find.byType(Scaffold)).width;
      final rtl = dir == TextDirection.rtl;
      final fromStart = rtl
          ? width - t.getTopRight(text).dx
          : t.getTopLeft(text).dx;
      expect(fromStart, moreOrLessEquals(indent, epsilon: 0.5));
    }

    testWidgets('afterIcon lines up with ListTile text (${dir.name})', (
      t,
    ) async {
      await check(
        t,
        const ListTile(leading: Icon(Icons.print), title: Text('طباعة')),
        TashilDividerInset.afterIcon,
        find.byType(ListTile).evaluate().isEmpty
            ? find.text('طباعة')
            : find
                  .ancestor(
                    of: find.text('طباعة'),
                    matching: find.byType(DefaultTextStyle),
                  )
                  .first,
      );
    });

    testWidgets('afterThumbnail lines up with ProductTile text (${dir.name})', (
      t,
    ) async {
      await check(
        t,
        const ProductTile(
          name: 'سكر',
          pricePiastres: 4550,
          stock: 3,
          minStock: 1,
        ),
        TashilDividerInset.afterThumbnail,
        find
            .ancestor(
              of: find.text('سكر'),
              matching: find.byType(DefaultTextStyle),
            )
            .first,
      );
    });
  }
}
