import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// TAS-78: the app defaults to ENV=dev, so every store/prod build command must
/// ask for prod explicitly. A release built without it would talk to
/// tashil-dev.
void main() {
  const prodBuilds = <String, String>{
    '.github/workflows/android-release.yml': 'flutter build appbundle',
    '.github/workflows/deploy-ios.yml': 'flutter build ios',
    'scripts/build_web.sh': 'flutter build web --release --dart-define=ENV=prod',
  };

  for (final entry in prodBuilds.entries) {
    test('${entry.key} builds with --dart-define=ENV=prod', () {
      final lines = File(entry.key)
          .readAsLinesSync()
          .where((l) => l.contains(entry.value))
          .toList();
      expect(lines, isNotEmpty, reason: 'no "${entry.value}" in ${entry.key}');
      for (final l in lines) {
        expect(l, contains('--dart-define=ENV=prod'), reason: l.trim());
      }
    });
  }
}
