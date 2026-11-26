import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:delegate_app/core/design/tokens.dart';
import 'package:delegate_app/features/playground/playground_screen.dart';
import 'package:delegate_app/main_playground.dart';

/// SUNMI V3: 720 px wide at ~2x density -> 360 dp compact window.
const sunmiV3 = Size(360, 780);

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('every playground tab renders on SUNMI V3 '
        '(${brightness.name}) without overflow', (tester) async {
      tester.view.physicalSize = sunmiV3 * 2;
      tester.view.devicePixelRatio = 2;
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearAllTestValues);

      await tester.pumpWidget(const PlaygroundApp());
      await tester.pumpAndSettle();

      expect(
        Theme.of(tester.element(find.byType(TabBar).first)).brightness,
        brightness,
      );
      expect(
        Directionality.of(tester.element(find.byType(TabBar).first)),
        TextDirection.rtl,
      );

      for (var i = 0; i < PlaygroundScreen.tabs.length; i++) {
        DefaultTabController.of(tester.element(find.byType(TabBarView).first))
            .animateTo(i);
        await _settle(tester);
        // Scroll the whole tab so every section is built and laid out.
        // The section list of the tab that is on screen.
        final lists = find
            .descendant(
              of: find.byType(TabBarView).first,
              matching: find.byType(ListView),
            )
            .evaluate()
            .where((e) {
              final box = e.renderObject! as RenderBox;
              return box.localToGlobal(Offset.zero).dx.abs() < 1;
            })
            .toList();
        expect(lists, isNotEmpty, reason: 'tab $i has a section list');
        expect(
          DefaultTabController.of(tester.element(find.byType(TabBarView).first))
              .index,
          i,
        );
        final position = tester
            .state<ScrollableState>(
              find
                  .descendant(
                    of: find.byElementPredicate((e) => e == lists.first),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            )
            .position;
        // Jump rather than drag: nested demo lists would swallow drags.
        for (var s = 0; s < 60 && position.extentAfter > 0; s++) {
          position.jumpTo(
            (position.pixels + 400).clamp(0, position.maxScrollExtent),
          );
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(position.extentAfter, 0, reason: 'tab $i fully scrolled');
        await _settle(tester);
        expect(tester.takeException(), isNull, reason: 'tab $i');
      }
    });
  }

  test('semantic colours exist for both brightnesses', () {
    for (final b in Brightness.values) {
      final c = TashilSemanticColors.forBrightness(b);
      expect(c.success, isNot(c.warning));
    }
  });
}

/// Like pumpAndSettle, but bounded: indeterminate progress indicators in the
/// playground animate forever, so pumpAndSettle would time out.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
