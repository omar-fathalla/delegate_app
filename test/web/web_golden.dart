import 'package:flutter_test/flutter_test.dart';

/// Web desktop goldens are recorded on the macOS CI runner's renderer and do
/// not match other hosts, so they only run on request:
/// `flutter test --dart-define=WEB_GOLDENS=true test/web`
/// (add `--update-goldens` on macOS to re-record).
const bool kWebGoldens = bool.fromEnvironment('WEB_GOLDENS');

Future<void> expectWebGolden(Finder finder, String path) async {
  if (!kWebGoldens) return;
  await expectLater(finder, matchesGoldenFile(path));
}
