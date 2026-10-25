import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('client source has no hardcoded super-admin password or identity', () {
    const forbidden = <String>[
      '481636100Aa!',
      '01508899965000',
      'Cq7Xa6OEwEOlRPlS41vohtfBXke2',
      'omar.fathalla80800@icloud.com',
    ];
    final hits = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final text = entity.readAsStringSync();
      for (final secret in forbidden) {
        if (text.contains(secret)) {
          hits.add('${entity.path} contains a removed credential');
        }
      }
    }
    expect(hits, isEmpty);
  });
}
