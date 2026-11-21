import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// SHA-256 of credentials that were once hardcoded in `lib/` and removed.
/// Kept as hashes so the repo never shows them in plain text (TAS-179).
const _removedCredentialHashes = <String>{
  // old super-admin password
  '0507df8389c232463d5e02a72897d6759b72a1b86921bde630ea3d1dd4ef065a',
  // old super-admin phone/id
  'fe3203b286bfb5dbc7b7ce029403caebb39f41a0af74daa02aa437515f97db95',
  // old super-admin Firebase UID
  '1df7eb4f7b1039ab102cd647a7b7afd6fe15ce6f2599105c436cea8136bfc570',
  // old super-admin email
  '829efe92d29820f980dcde588fe83f9afc7b7f4c1383baad741bfeeeb0b0d9e1',
};

// Single- or double-quoted Dart string literals (one line).
final _stringLiteral = RegExp(r"'((?:[^'\\\n]|\\.)*)'" '|' r'"((?:[^"\\\n]|\\.)*)"');
final _tokenSplit = RegExp(r'[^A-Za-z0-9@._!+-]+');

String _sha256(String s) => sha256.convert(utf8.encode(s)).toString();

void main() {
  test('client source has no hardcoded super-admin credential or anonymous sign-in', () {
    final hits = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final text = entity.readAsStringSync();
      if (text.contains('signInAnonymously')) {
        hits.add('${entity.path} calls signInAnonymously');
      }
      for (final m in _stringLiteral.allMatches(text)) {
        final literal = m.group(1) ?? m.group(2) ?? '';
        final candidates = <String>{literal, ...literal.split(_tokenSplit)};
        if (candidates.any((c) => c.isNotEmpty && _removedCredentialHashes.contains(_sha256(c)))) {
          hits.add('${entity.path} contains a removed credential');
          break;
        }
      }
    }
    expect(hits, isEmpty);
  });

  test('the hash check catches a credential when it is present', () {
    // Self-check with a throwaway value, so the guard is known to work.
    const probe = 'probe-credential-123';
    final hashes = {_sha256(probe)};
    final text = "const x = 'user: $probe';";
    final found = _stringLiteral.allMatches(text).any((m) {
      final literal = m.group(1) ?? m.group(2) ?? '';
      return {literal, ...literal.split(_tokenSplit)}.any((c) => hashes.contains(_sha256(c)));
    });
    expect(found, isTrue);
  });
}
