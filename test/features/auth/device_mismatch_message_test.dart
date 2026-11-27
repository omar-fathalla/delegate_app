import 'package:delegate_app/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:flutter_test/flutter_test.dart';

/// TAS-367: a delegate locked on a new device sees who to call.
void main() {
  test('with supervisor and request age', () {
    final now = DateTime(2026, 11, 28, 12);
    final msg = deviceMismatchMessage({
      'supervisorName': 'أحمد',
      'supervisorPhone': '01000000021',
      'requestCreatedAtMs': now.subtract(const Duration(hours: 3)).millisecondsSinceEpoch,
    }, now: now);
    expect(msg, contains('كلّم المشرف أحمد'));
    expect(msg, contains('01000000021'));
    expect(msg, contains('بقاله 3 ساعة'));
  });

  test('old server without details: the old message', () {
    expect(deviceMismatchMessage(const {}), startsWith('هذا الحساب مقترن بجهاز آخر'));
    expect(deviceMismatchMessage(const {}), isNot(contains('كلّم المشرف')));
  });
}
