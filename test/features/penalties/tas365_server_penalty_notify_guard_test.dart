import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// TAS-365: the staff app no longer writes the delegate's penalty
/// notification (onPenaltyCreated / onPenaltyUpdated do), and marks its
/// status changes for the server (notifyByServerAt next to updatedAt).
/// Writing both would send the delegate two pushes.
void main() {
  const path =
      'lib/features/penalties/data/datasources/penalty_remote_data_source.dart';

  test('no client notification to the penalty\'s delegate', () {
    final src = File(path).readAsStringSync();
    expect(src.contains("'delegateUid': targetDelId"), isFalse);
    expect(src.contains("'delegateUid': pen.targetDelegateId"), isFalse);
    expect(src.contains('تسجيل مخالفة جديدة بحقك'), isFalse);
  });

  test('status changes carry the server marker', () {
    final src = File(path).readAsStringSync();
    expect(src.contains("'notifyByServerAt': FieldValue.serverTimestamp()"),
        isTrue);
  });
}
