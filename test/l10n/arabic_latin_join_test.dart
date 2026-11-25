import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// TAS-340: an Arabic letter glued to a Latin word (e.g. «وRealme») renders
/// as garbage inside RTL text on Android («Realmeg»), and so does a standalone
/// «و» in the app font. Keep words apart and avoid a lone «و».
void main() {
  test('Arabic strings never glue an Arabic letter to a Latin word', () {
    final arb = jsonDecode(File('lib/l10n/app_ar.arb').readAsStringSync())
        as Map<String, dynamic>;
    final glued = RegExp(r'[\u0600-\u06FF][A-Za-z]|(^|\s)\u0648(\s|$)');
    final offenders = <String>[];
    arb.forEach((key, value) {
      if (key.startsWith('@') || value is! String) return;
      if (glued.hasMatch(value)) offenders.add(key);
    });
    expect(offenders, isEmpty);
  });
}
