import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// TAS-371: the staff app marks a leave / device-change decision for the
/// server (`notifyByServer: true`) and no longer writes the delegate's
/// notification itself (onLeaveRequestDecided / onUnbindRequestDecided do).
/// Writing both would send the delegate two pushes.
void main() {
  final files = {
    'lib/features/hr/presentation/pages/hr_leaves_and_excuses_screen.dart': [
      'leave_approved',
      'leave_rejected',
    ],
    'lib/core/services/device_binding_service.dart': [
      'device_unbound',
      'device_unbind_rejected',
    ],
  };

  for (final entry in files.entries) {
    test('${entry.key}: decisions go to the server', () {
      final src = File(entry.key).readAsStringSync();
      expect(
        RegExp(r"'notifyByServer': true").allMatches(src).length,
        2,
        reason: 'approve and reject both set the marker',
      );
      for (final type in entry.value) {
        expect(
          src.contains("'type': '$type'"),
          isFalse,
          reason: '$type is written by the server now',
        );
      }
    });
  }
}
