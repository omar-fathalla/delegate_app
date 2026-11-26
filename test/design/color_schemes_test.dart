import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:delegate_app/core/design/app_localizations.dart';
import 'package:delegate_app/core/design/color_schemes.dart';
import 'package:delegate_app/core/design/tokens.dart';
import 'package:delegate_app/core/design/widgets/color_scheme_picker.dart';

Future<TashilColorController> _app(WidgetTester t, Widget child) async {
  t.view.physicalSize = const Size(400, 1000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final c = TashilColorController();
  addTearDown(c.dispose);
  await t.pumpWidget(
    TashilColorScope(
      controller: c,
      builder: (context, themes) => MaterialApp(
        theme: themes.light,
        locale: TashilLocale.arabic,
        supportedLocales: TashilLocale.supported,
        localizationsDelegates: TashilLocale.delegates,
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
  return c;
}

Color _primary(WidgetTester t) =>
    Theme.of(t.element(find.byType(Scaffold))).colorScheme.primary;

void main() {
  test('each source gives its own seed; wallpaper falls back to brand', () {
    const s = TashilColorSettings();
    expect(s.seed(), TashilColors.seed);
    expect(
      s
          .copyWith(
            source: TashilColorSource.store,
            storeColor: storeColorPresets[1],
          )
          .seed(),
      storeColorPresets[1],
    );
    expect(s.copyWith(source: TashilColorSource.baseline).seed(), baselineSeed);
    final w = s.copyWith(source: TashilColorSource.wallpaper);
    expect(w.seed(), TashilColors.seed);
    expect(w.seed(wallpaper: const Color(0xFFAA0000)), const Color(0xFFAA0000));
  });

  test('fidelity switches the algorithm, never for baseline', () {
    const s = TashilColorSettings(fidelity: true);
    expect(s.variant, DynamicSchemeVariant.fidelity);
    expect(
      s.copyWith(source: TashilColorSource.baseline).variant,
      DynamicSchemeVariant.tonalSpot,
    );
    expect(const TashilColorSettings().variant, DynamicSchemeVariant.tonalSpot);
  });

  test('every source keeps text pairs readable', () {
    for (final seed in [
      TashilColors.seed,
      baselineSeed,
      ...storeColorPresets,
    ]) {
      for (final fidelity in [false, true]) {
        for (final b in Brightness.values) {
          final s = ColorScheme.fromSeed(
            seedColor: seed,
            brightness: b,
            dynamicSchemeVariant: fidelity
                ? DynamicSchemeVariant.fidelity
                : DynamicSchemeVariant.tonalSpot,
          );
          for (final (bg, fg) in [
            (s.primary, s.onPrimary),
            (s.primaryContainer, s.onPrimaryContainer),
            (s.secondaryContainer, s.onSecondaryContainer),
            (s.surface, s.onSurface),
          ]) {
            expect(contrastRatio(bg, fg), greaterThanOrEqualTo(4.5));
          }
        }
      }
    }
  });

  testWidgets('picker: store colour and contrast recolour the app', (t) async {
    final c = await _app(t, const ColorSchemePicker());
    final brand = _primary(t);

    await t.tap(find.text('لون المحل'));
    await t.pumpAndSettle();
    expect(c.value.source, TashilColorSource.store);
    final store = _primary(t);
    expect(store, isNot(brand));

    await t.tap(find.bySemanticsLabel(RegExp('C62828')));
    await t.pumpAndSettle();
    expect(c.value.storeColor, storeColorPresets[1]);
    expect(_primary(t), isNot(store));

    await t.tap(find.text('عالي'));
    await t.pumpAndSettle();
    expect(c.value.contrast, TashilContrast.high);
  });

  testWidgets('picker: wallpaper says when the device cannot do it', (t) async {
    await _app(t, const ColorSchemePicker());
    expect(find.textContaining('مش بيدعمها'), findsOneWidget);
  });

  testWidgets('content colour recolours only its area', (t) async {
    late ImageProvider image;
    await t.runAsync(() async {
      final rec = ui.PictureRecorder();
      Canvas(rec).drawRect(
        const Rect.fromLTWH(0, 0, 32, 32),
        Paint()..color = const Color(0xFFFF9800),
      );
      final img = await rec.endRecording().toImage(32, 32);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      image = MemoryImage(Uint8List.view(bytes!.buffer));
    });
    // The scheme is worked out from the image asynchronously, outside the
    // fake test clock.
    await t.runAsync(() async {
      await _app(
        t,
        Column(
          children: [
            const Text('بره', key: Key('out')),
            ContentColorScope(
              image: image,
              child: const Text('جوه', key: Key('in')),
            ),
          ],
        ),
      );
      await Future<void>.delayed(const Duration(seconds: 1));
    });
    await t.pump();
    final out = Theme.of(t.element(find.byKey(const Key('out')))).colorScheme;
    final inside = Theme.of(t.element(find.byKey(const Key('in')))).colorScheme;
    expect(inside.primary, isNot(out.primary));
    final hue = HSLColor.fromColor(inside.primaryContainer).hue;
    expect(hue, inInclusiveRange(15, 60), reason: 'orange from the image');
  });
}
