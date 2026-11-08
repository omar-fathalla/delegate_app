import '../../patrol_test/support/smoke_login_wait.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('smokeDevLoginFieldValueKeys', () {
    test('delegate (default مندوب) waits on national ID not staff password', () {
      final keys = smokeDevLoginFieldValueKeys(SmokeDevLoginFieldMode.delegate);
      expect(keys, ['login_phone', 'login_national_id']);
      expect(keys, isNot(contains('login_staff_password')));
    });

    test('staff waits on staff password after mode switch', () {
      final keys = smokeDevLoginFieldValueKeys(SmokeDevLoginFieldMode.staff);
      expect(keys, ['login_phone', 'login_staff_password']);
      expect(keys, isNot(contains('login_national_id')));
    });
  });
}
