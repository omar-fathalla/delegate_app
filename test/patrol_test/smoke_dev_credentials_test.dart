import 'package:flutter_test/flutter_test.dart';

import '../../patrol_test/support/smoke_dev_credentials.dart';

void main() {
  test('default supervisor phone and role label', () {
    const creds = SmokeDevPatrolCredentials(
      phone: SmokeDevPatrolCredentials.defaultPhone,
      secret: 'test-only',
      expectedRoleLabel: SmokeDevPatrolCredentials.defaultSupervisorRoleLabel,
    );
    expect(creds.phone, '01500000002');
    expect(creds.expectedRoleLabel, 'مشرف (Supervisor)');
    expect(creds.hasSecret, isTrue);
  });

  test('fromEnvironment without secret has hasSecret false', () {
    final creds = SmokeDevPatrolCredentials.fromEnvironment();
    expect(creds.phone, isNotEmpty);
    expect(creds.expectedRoleLabel, isNotEmpty);
  });
}
