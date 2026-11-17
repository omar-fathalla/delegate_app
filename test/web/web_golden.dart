import 'package:flutter_test/flutter_test.dart';

/// Golden pixels depend on the host renderer (the CI runner is macOS), so the
/// web desktop goldens only run on request:
/// `flutter test --dart-define=WEB_GOLDENS=true test/web`
/// (add `--update-goldens` on macOS to re-record).
const bool kWebGoldens = bool.fromEnvironment('WEB_GOLDENS');

Future<void> expectWebGolden(Finder finder, String path) async {
  if (!kWebGoldens) return;
  await expectLater(finder, matchesGoldenFile(path));
}
