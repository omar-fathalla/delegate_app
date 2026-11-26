import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// TAS-386: the new-request form shows one time wheel at a time, switched by
/// a «من | إلى» ButtonGroup. Two stacked wheels covered most of the form and
/// took the drag meant to scroll it (seen on the M31). The screen reads
/// Firestore directly, so this guards the source.
void main() {
  test('one ScrollTimePicker, switched by a from/to ButtonGroup', () {
    final src = File(
      'lib/features/hr/presentation/pages/delegate_leaves_and_requests_screen.dart',
    ).readAsStringSync();
    expect(RegExp(r'ScrollTimePicker\(').allMatches(src).length, 1);
    expect(src, contains("Key('newRequestTimeSide')"));
    expect(src, contains('ButtonGroup<bool>('));
  });
}
