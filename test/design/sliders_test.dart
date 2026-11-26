import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:delegate_app/core/design/app_theme.dart';
import 'package:delegate_app/core/design/widgets/sliders.dart';

Future<void> _app(WidgetTester t, Widget child) async {
  t.view.physicalSize = const Size(400, 600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: TashilTheme.light(),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Center(child: SizedBox(width: 300, child: child)),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('theme opts into the 2024 slider', (t) async {
    await _app(t, Slider(value: 0.5, onChanged: (_) {}));
    final theme = SliderTheme.of(t.element(find.byType(Slider)));
    // ignore: deprecated_member_use
    expect(theme.year2023, isFalse);
  });

  testWidgets('sizes set track height; handle narrows while pressed', (
    t,
  ) async {
    for (final s in SliderSize.values) {
      await _app(t, TashilSlider(value: 0.5, size: s, onChanged: (_) {}));
      final theme = SliderTheme.of(t.element(find.byType(Slider)));
      expect(theme.trackHeight, s.trackHeight);
      expect(theme.thumbSize!.resolve({}), Size(4, s.handleHeight));
      expect(
        theme.thumbSize!.resolve({WidgetState.pressed}),
        Size(2, s.handleHeight),
      );
    }
  });

  testWidgets('inset icon: on the active track, moves after the handle, '
      'swaps at zero', (t) async {
    var value = 0.8;
    late StateSetter set;
    await _app(
      t,
      StatefulBuilder(
        builder: (c, s) {
          set = s;
          return TashilSlider(
            value: value,
            size: SliderSize.l,
            insetIcon: (v) => v == 0 ? Icons.volume_off : Icons.volume_up,
            onChanged: (v) => s(() => value = v),
          );
        },
      ),
    );
    final slider = t.getRect(find.byType(Slider));
    // RTL: the start (minimum) is on the right.
    expect(
      t.getRect(find.byIcon(Icons.volume_up)).right,
      closeTo(slider.right - 12, 1),
    );

    set(() => value = 0.05);
    await t.pump();
    final icon = t.getRect(find.byIcon(Icons.volume_up));
    final handleX = slider.right - 0.05 * slider.width;
    expect(icon.right, lessThan(handleX), reason: 'on the inactive side');

    set(() => value = 0);
    await t.pump();
    expect(find.byIcon(Icons.volume_off), findsOneWidget);
  });

  testWidgets('no inset icon under a 40dp track', (t) async {
    await _app(
      t,
      TashilSlider(
        value: 0.5,
        size: SliderSize.s,
        insetIcon: (_) => Icons.print,
        onChanged: (_) {},
      ),
    );
    expect(t.takeException(), isAssertionError);
  });

  testWidgets('vertical: minimum at the bottom, also in RTL', (t) async {
    var value = 0.5;
    await _app(
      t,
      SizedBox(
        height: 200,
        child: StatefulBuilder(
          builder: (c, s) => TashilSlider(
            value: value,
            vertical: true,
            onChanged: (v) => s(() => value = v),
          ),
        ),
      ),
    );
    expect(t.widget<RotatedBox>(find.byType(RotatedBox)).quarterTurns, 3);
    final r = t.getRect(find.byType(Slider));
    await t.tapAt(Offset(r.center.dx, r.top + 20));
    await t.pump();
    expect(value, greaterThan(0.8));
  });

  testWidgets('centered: active track only between the middle and handle', (
    t,
  ) async {
    var value = 0.0;
    late StateSetter set;
    await _app(
      t,
      StatefulBuilder(
        builder: (c, s) {
          set = s;
          return CenteredSlider(
            value: value,
            min: -10,
            max: 10,
            onChanged: (v) => s(() => value = v),
          );
        },
      ),
    );
    final slider = find.byType(Slider);
    // Two inactive pieces plus the handle at the centre...
    expect(slider, paintsExactlyCountTimes(#drawRRect, 3));
    set(() => value = 6);
    await t.pump();
    // ...and an active piece once the handle moves away from it.
    expect(slider, paintsExactlyCountTimes(#drawRRect, 4));
  });
}
