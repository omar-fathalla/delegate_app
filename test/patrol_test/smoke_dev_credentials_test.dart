import 'package:flutter_test/flutter_test.dart';

import '../../patrol_test/support/smoke_dev_credentials.dart';

void main() {
  test('staff supervisor phone maps to profile company-admin badge', () {
    expect(
      SmokeDevPatrolCredentials.expectedProfileRoleLabelForPatrolPhone(
        SmokeDevPatrolCredentials.defaultStaffPhone,
      ),
      SmokeDevPatrolCredentials.staffSupervisorProfileRoleLabel,
    );
    expect(
      SmokeDevPatrolCredentials.staffSupervisorProfileRoleLabel,
      'مشرف الشركة (Company Admin)',
    );
  });

  test('unknown dev phone requires explicit PATROL_DEV_ROLE_LABEL', () {
    expect(
      () => SmokeDevPatrolCredentials.expectedProfileRoleLabelForPatrolPhone(
        '01999999999',
      ),
      throwsArgumentError,
    );
  });

  test('fromEnvironment without secret has hasSecret false', () {
    final creds = SmokeDevPatrolCredentials.fromEnvironment();
    expect(creds.phone, SmokeDevPatrolCredentials.defaultStaffPhone);
    expect(
      creds.expectedRoleLabel,
      SmokeDevPatrolCredentials.staffSupervisorProfileRoleLabel,
    );
    expect(creds.hasSecret, isFalse);
  });

  test('delegateFromEnvironment exposes fake national ID default', () {
    final creds = SmokeDevPatrolCredentials.delegateFromEnvironment();
    expect(creds.phone, SmokeDevPatrolCredentials.defaultDelegatePhone);
    expect(creds.nationalId, SmokeDevPatrolCredentials.defaultDelegateNationalId);
    expect(creds.hasDelegateNationalId, isTrue);
  });
}
