import 'package:delegate_app/features/admin/data/datasources/delegate_hold_remote.dart';
import 'package:delegate_app/features/admin/domain/entities/delegate_hold_access.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  bool check({
    required UserRole role,
    String callerOrg = 'o1',
    String callerCo = 'c1',
    String targetOrg = 'o1',
    String targetCo = 'c1',
  }) => canSetDelegateHold(
    role: role,
    callerOrganizationUID: callerOrg,
    callerCompanyUID: callerCo,
    targetOrganizationUID: targetOrg,
    targetCompanyUID: targetCo,
  );

  test('super-admin and technical support are global', () {
    expect(
      check(role: UserRole.superAdmin, callerOrg: '', callerCo: ''),
      isTrue,
    );
    expect(
      check(
        role: UserRole.technicalSupport,
        callerOrg: '',
        callerCo: '',
        targetOrg: 'o2',
        targetCo: 'c9',
      ),
      isTrue,
    );
  });

  test('org-admin is scoped to their organization', () {
    expect(check(role: UserRole.organizationAdmin), isTrue);
    expect(check(role: UserRole.organizationAdmin, targetOrg: 'o2'), isFalse);
    expect(check(role: UserRole.organizationAdmin, callerOrg: ''), isFalse);
  });

  test(
    'company admin and supervisor (UserRole.admin) match and fail closed',
    () {
      expect(check(role: UserRole.admin), isTrue);
      expect(check(role: UserRole.admin, callerCo: ''), isFalse);
      expect(check(role: UserRole.admin, targetCo: 'c2'), isFalse);
      expect(check(role: UserRole.admin, targetOrg: 'o2'), isFalse);
    },
  );

  test('hr and other staff cannot set holds', () {
    expect(check(role: UserRole.hr), isFalse);
    expect(check(role: UserRole.accountant), isFalse);
    expect(check(role: UserRole.marketing), isFalse);
    expect(check(role: UserRole.delegate), isFalse);
  });

  test('company supervisor suspends only their company and only status', () {
    final own = buildDelegateHoldPayload(
      callerRole: UserRole.admin,
      callerOrganizationUID: 'o1',
      callerCompanyUID: 'c1',
      uid: 'd1',
      organizationUID: 'o1',
      companyUID: 'c1',
      op: 'add',
    );
    expect(own, isNotNull);
    expect(own!.keys.toSet(), {'uid', 'orgId', 'companyId', 'hold', 'op'});
    expect(own['hold'], companySupervisorStatusHold);
    expect(own.keys, isNot(contains('fullName')));
    expect(own.keys, isNot(contains('phoneNumber')));
    expect(own.keys, isNot(contains('statusReason')));

    expect(
      buildDelegateHoldPayload(
        callerRole: UserRole.admin,
        callerOrganizationUID: 'o1',
        callerCompanyUID: 'c1',
        uid: 'd2',
        organizationUID: 'o1',
        companyUID: 'c2',
        op: 'add',
      ),
      isNull,
    );
    expect(
      buildDelegateHoldPayload(
        callerRole: UserRole.admin,
        callerOrganizationUID: 'o1',
        callerCompanyUID: '',
        uid: 'd1',
        organizationUID: 'o1',
        companyUID: 'c1',
        op: 'add',
      ),
      isNull,
    );
    expect(
      buildDelegateHoldPayload(
        callerRole: UserRole.admin,
        callerOrganizationUID: 'o1',
        callerCompanyUID: 'c1',
        uid: 'd1',
        organizationUID: 'o1',
        companyUID: 'c1',
        op: 'add',
        hold: 'subscription_expired',
      ),
      isNull,
    );
    expect(
      buildDelegateHoldPayload(
        callerRole: UserRole.admin,
        callerOrganizationUID: 'o1',
        callerCompanyUID: 'c1',
        uid: 'd1',
        organizationUID: 'o1',
        companyUID: 'c1',
        op: 'remove',
      ),
      isNull,
    );
    expect(
      delegateHoldOpFor(callerRole: UserRole.admin, suspend: false),
      isNull,
    );
    expect(delegateHoldOpFor(callerRole: UserRole.admin, suspend: true), 'add');
    expect(
      delegateHoldOpFor(callerRole: UserRole.superAdmin, suspend: false),
      'remove',
    );
    final lifted = buildDelegateHoldPayload(
      callerRole: UserRole.superAdmin,
      callerOrganizationUID: '',
      callerCompanyUID: '',
      uid: 'd1',
      organizationUID: 'o1',
      companyUID: 'c1',
      op: 'remove',
    );
    expect(lifted?['op'], 'remove');
  });

  test('hold_not_allowed maps to the supervisor Arabic message', () {
    expect(
      delegateHoldFailureMessage('hold_not_allowed'),
      delegateHoldNotAllowedMessage,
    );
    expect(delegateHoldNotAllowedMessage, isNot(contains('تعذر')));
  });
}
