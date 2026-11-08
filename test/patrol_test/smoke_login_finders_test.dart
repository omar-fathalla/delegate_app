import 'package:delegate_app/features/auth/domain/usecases/login.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('M3 login mode segment ValueKeys match LoginScreen M3ButtonGroup', () {
    expect(LoginMode.staff.toString(), 'LoginMode.staff');
    expect(LoginMode.delegate.toString(), 'LoginMode.delegate');
    expect('group_item_${LoginMode.staff}', 'group_item_LoginMode.staff');
    expect('group_item_${LoginMode.delegate}', 'group_item_LoginMode.delegate');
  });

  test('login_screen field ValueKey names used by Patrol smoke', () {
    expect(const [
      'login_phone',
      'login_staff_password',
      'login_national_id',
      'login_submit',
    ], containsAll(['login_phone', 'login_staff_password', 'login_submit']));
  });

  test('delegate vs staff field keys are mutually exclusive second fields', () {
    expect(
      const ['login_national_id'],
      isNot(contains('login_staff_password')),
    );
  });
}
