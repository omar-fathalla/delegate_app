import 'dart:async';
import 'dart:io' show File, Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show FontWeight;
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// Max share of differing pixels a golden may have and still pass (TAS-195).
///
/// Mac and Linux render the same golden 0.5%-6.2% differently (measured on
/// PR #427), far too much for one tolerance. So each host OS compares against
/// its own images (see [TolerantGoldenFileComparator.getTestUri]) and this
/// tolerance only absorbs small drift on the same OS (e.g. Flutter upgrades).
/// 0.5% of a 780x1688 golden is ~6.5k pixels, below a real change (one
/// changed chip label was 1.09%).
const double kGoldenDiffTolerance = 0.005;

/// Runs before every test file in `test/`. Only affects `matchesGoldenFile`,
/// i.e. the golden tests (tag `golden`, see dart_test.yaml).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await _preloadCairoFonts();
  final current = goldenFileComparator;
  if (current is LocalFileComparator) {
    goldenFileComparator = TolerantGoldenFileComparator(
      // basedir is the test file's directory; any file name inside it works.
      Uri.parse('${current.basedir}flutter_test_config.dart'),
      tolerance: kGoldenDiffTolerance,
    );
  }
  await testMain();
}

/// Bundled Cairo weights (see `fonts:` in pubspec.yaml).
const _bundledCairoWeights = <FontWeight>[
  FontWeight.w200,
  FontWeight.w300,
  FontWeight.w400,
  FontWeight.w500,
  FontWeight.w600,
  FontWeight.w700,
  FontWeight.w900,
];

/// Loads the bundled Cairo fonts once per test file, before any widget tree.
///
/// GoogleFonts loads a font the first time a widget asks for it. When the load
/// finishes the engine sends a `fontsChange` system message, and every
/// attached text render object schedules a frame callback. Since Flutter 3.50
/// `postTest` checks for pending frame callbacks only after the test's
/// `addTearDown`s ran, so a load that finishes during teardown fails the
/// first widget test of a file with "An animation is still running even after
/// the widget tree was disposed". Loading the fonts here, while no render
/// object exists, keeps that message out of the tests.
Future<void> _preloadCairoFonts() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  // TAS-348: the theme uses the bundled Cairo variable font as family
  // 'Cairo' (pubspec `fonts:`). Tests do not load pubspec fonts by
  // themselves, so without this every theme text falls back to the wide test
  // font and layouts overflow only in tests.
  final cairo = File('assets/fonts/cairo-variable/Cairo-Variable.ttf');
  if (cairo.existsSync()) {
    final bytes = cairo.readAsBytesSync();
    final loader = FontLoader('Cairo')
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  }
  for (final weight in _bundledCairoWeights) {
    GoogleFonts.cairo(fontWeight: weight);
  }
  try {
    await GoogleFonts.pendingFonts();
  } catch (_) {
    // A font that fails to load here fails the same way inside the test.
  }
  // Let the `fontsChange` message reach the binding before tests start.
  await Future<void>.delayed(Duration.zero);
}

/// [LocalFileComparator] that accepts diffs up to [tolerance] (0..1) and keeps
/// Linux goldens apart from the Mac ones.
class TolerantGoldenFileComparator extends LocalFileComparator {
  TolerantGoldenFileComparator(super.testFile, {required this.tolerance})
    : assert(tolerance >= 0 && tolerance < 0.01);

  final double tolerance;

  /// On Linux (CI), `dir/name.png` resolves to `dir/linux/name.png`; Macs use
  /// `dir/name.png`. Applies to compare and `--update-goldens` alike, so
  /// re-recording on Linux writes the Linux set.
  @override
  Uri getTestUri(Uri key, int? version) {
    final uri = super.getTestUri(key, version);
    if (!Platform.isLinux) return uri;
    final segments = [...uri.pathSegments];
    segments.insert(segments.length - 1, 'linux');
    return uri.replace(pathSegments: segments);
  }

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    if (result.passed || result.diffPercent <= tolerance) {
      if (!result.passed) {
        // ignore: avoid_print
        print(
          'Golden "$golden" within tolerance: '
          '${(result.diffPercent * 100).toStringAsFixed(3)}% diff '
          '(limit ${(tolerance * 100).toStringAsFixed(2)}%).',
        );
      }
      result.dispose();
      return true;
    }
    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}
