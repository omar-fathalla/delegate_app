import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

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
