import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:delegate_app/core/design/app_theme.dart';
import 'package:delegate_app/core/design/tokens.dart';

/// Every fill with the "on" colour M3 pairs it with.
List<(String, Color, Color)> _pairs(ThemeData t) {
  final s = t.colorScheme;
  final sem = t.extension<TashilSemanticColors>()!;
  return [
    ('primary', s.primary, s.onPrimary),
    ('primaryContainer', s.primaryContainer, s.onPrimaryContainer),
    ('secondary', s.secondary, s.onSecondary),
    ('secondaryContainer', s.secondaryContainer, s.onSecondaryContainer),
    ('tertiary', s.tertiary, s.onTertiary),
    ('tertiaryContainer', s.tertiaryContainer, s.onTertiaryContainer),
    ('error', s.error, s.onError),
    ('errorContainer', s.errorContainer, s.onErrorContainer),
    ('surface', s.surface, s.onSurface),
    ('surfaceContainer', s.surfaceContainer, s.onSurface),
    ('surfaceVariantText', s.surfaceContainerHighest, s.onSurfaceVariant),
    ('inverseSurface', s.inverseSurface, s.onInverseSurface),
    ('inversePrimary', s.inverseSurface, s.inversePrimary),
    ('primaryFixed', s.primaryFixed, s.onPrimaryFixed),
    ('success', sem.success, sem.onSuccess),
    ('successContainer', sem.successContainer, sem.onSuccessContainer),
    ('warning', sem.warning, sem.onWarning),
    ('warningContainer', sem.warningContainer, sem.onWarningContainer),
  ];
}

ThemeData _theme(Brightness b, TashilContrast c) => b == Brightness.light
    ? TashilTheme.light(contrast: c)
    : TashilTheme.dark(contrast: c);

void main() {
  for (final b in Brightness.values) {
    for (final c in TashilContrast.values) {
      test('${b.name} ${c.name}: pairs readable, outlines visible', () {
        final t = _theme(b, c);
        // M3: text pairs reach 4.5:1; high contrast aims for 7:1.
        final min = c == TashilContrast.high ? 7.0 : 4.5;
        for (final (name, bg, fg) in _pairs(t)) {
          expect(
            contrastRatio(bg, fg),
            greaterThanOrEqualTo(min),
            reason: name,
          );
        }
        final s = t.colorScheme;
        // Important boundaries (text field outline) need 3:1.
        expect(contrastRatio(s.surface, s.outline), greaterThanOrEqualTo(3));
        if (c != TashilContrast.standard) {
          // Medium and high: 3:1 everywhere, dividers too.
          expect(
            contrastRatio(s.surface, s.outlineVariant),
            greaterThanOrEqualTo(3),
          );
        }
      });
    }
  }

  test('higher levels raise contrast; standard is the default', () {
    double primary(TashilContrast c) {
      final s = TashilTheme.light(contrast: c).colorScheme;
      return contrastRatio(s.primary, s.onPrimary);
    }

    expect(
      primary(TashilContrast.medium),
      greaterThan(primary(TashilContrast.standard)),
    );
    expect(
      primary(TashilContrast.high),
      greaterThan(primary(TashilContrast.medium)),
    );
    expect(
      TashilTheme.light().colorScheme,
      TashilTheme.light(contrast: TashilContrast.standard).colorScheme,
    );
  });

  test('error stays error-red whatever the seed (static role)', () {
    final s = TashilTheme.light().colorScheme;
    final hue = HSLColor.fromColor(s.error).hue;
    expect(hue < 30 || hue > 330, isTrue);
  });

  test('fixed roles keep the same colour in light and dark', () {
    final l = TashilTheme.light().colorScheme;
    final d = TashilTheme.dark().colorScheme;
    expect(l.primaryFixed, d.primaryFixed);
    expect(l.surface, isNot(d.surface));
  });

  testWidgets('apps use the high-contrast theme when the system asks', (
    t,
  ) async {
    t.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(highContrast: true);
    addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
    late ColorScheme seen;
    await t.pumpWidget(
      MaterialApp(
        theme: TashilTheme.light(),
        highContrastTheme: TashilTheme.light(contrast: TashilContrast.high),
        home: Builder(
          builder: (c) {
            seen = Theme.of(c).colorScheme;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(
      seen.primary,
      TashilTheme.light(contrast: TashilContrast.high).colorScheme.primary,
    );
  });
}
