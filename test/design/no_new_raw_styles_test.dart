import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// TAS-348 ratchet: screens must take text sizes from `textTheme` and colours
/// from the colour roles (m3-catalog F-01, F-05). The app still has many
/// hand-written values from before the design system; this test only stops
/// the number from growing. When a screen is cleaned up (TAS-349..TAS-358),
/// lower the baseline to the new count in the same change.
///
/// Counted in `lib/` outside `lib/core/design/` (the design system itself),
/// `lib/features/playground/` (dev-only demos: the content-colour demo needs
/// fixed sample image colours; TAS-383) and generated files.
const _fontSizeBaseline = 1735; // TAS-357: penalties
const _hexColorBaseline = 400; // TAS-357: penalties

void main() {
  final fontSize = RegExp(r'\bfontSize\s*:');
  final hexColor = RegExp(
    r'\bColor\(\s*0x|Color\.fromARGB\(|Color\.fromRGBO\(',
  );

  ({int fontSize, int hex, Map<String, int> perFile}) count() {
    var sizes = 0;
    var hexes = 0;
    final perFile = <String, int>{};
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !f.path.contains('lib/core/design/'))
        .where((f) => !f.path.contains('lib/features/playground/'))
        .where((f) => !f.path.contains('/generated/'))
        .where((f) => !f.path.startsWith('lib/l10n'))
        .where((f) => !f.path.endsWith('.g.dart'))
        .where((f) => !f.path.endsWith('.freezed.dart'));
    for (final f in files) {
      final src = f.readAsStringSync();
      final s = fontSize.allMatches(src).length;
      final h = hexColor.allMatches(src).length;
      sizes += s;
      hexes += h;
      if (s + h > 0) perFile[f.path] = s + h;
    }
    return (fontSize: sizes, hex: hexes, perFile: perFile);
  }

  test('no new hand-written fontSize or hex colour in lib/', () {
    final c = count();
    expect(
      c.fontSize,
      lessThanOrEqualTo(_fontSizeBaseline),
      reason:
          'New `fontSize:` found (${c.fontSize} > $_fontSizeBaseline). Use '
          'Theme.of(context).textTheme instead (docs: m3-kit design-system.md, '
          'Typography).',
    );
    expect(
      c.hex,
      lessThanOrEqualTo(_hexColorBaseline),
      reason:
          'New hex colour found (${c.hex} > $_hexColorBaseline). Use '
          'Theme.of(context).colorScheme or TashilSemanticColors.of(context).',
    );
  });

  test('the design system itself has no hex colour outside tokens.dart', () {
    final offenders = Directory('lib/core/design')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !f.path.endsWith('tokens.dart'))
        .where((f) => !f.path.endsWith('color_schemes.dart'))
        .where((f) => hexColor.hasMatch(f.readAsStringSync()))
        .map((f) => f.path)
        .toList();
    expect(offenders, isEmpty);
  });
}
