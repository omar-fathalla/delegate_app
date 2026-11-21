import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Max share of differing pixels a golden may have and still pass (TAS-195).
///
/// Goldens are recorded on a Mac but CI runs them on Linux (ubuntu-latest).
/// Both use the bundled Cairo font (see `loadPromoTestFonts`), but text
/// antialiasing can still differ by a few edge pixels between hosts and Flutter
/// versions. 0.5% of a 780x1688 golden is ~6.5k pixels: enough for glyph-edge
/// noise, far below a real change (e.g. one changed chip label was 1.09%).
const double kGoldenDiffTolerance = 0.005;

/// Runs before every test file in `test/`. Only affects `matchesGoldenFile`,
/// i.e. the golden tests (tag `golden`, see dart_test.yaml).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
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

/// [LocalFileComparator] that accepts diffs up to [tolerance] (0..1).
class TolerantGoldenFileComparator extends LocalFileComparator {
  TolerantGoldenFileComparator(super.testFile, {required this.tolerance})
    : assert(tolerance >= 0 && tolerance < 0.01);

  final double tolerance;

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
