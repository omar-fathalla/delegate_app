import 'package:delegate_app/features/admin/domain/entities/delegate_profile_edit_access.dart';
import 'package:delegate_app/features/admin/domain/entities/delegate_subscription_request.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:flutter_test/flutter_test.dart';

DelegateSubscriptionRequest _pendingNewDelegate() => DelegateSubscriptionRequest(
      id: 'r1',
      supervisorUid: 'sup',
      supervisorName: 'مشرف',
      supervisorPhone: '01000000001',
      companyUID: 'c1',
      companyName: 'Co',
      organizationUID: 'o1',
      organizationName: 'Org',
      firstName: 'مندوب',
      secondName: '',
      thirdName: '',
      fullName: 'مندوب',
      phoneNumber: '01000000000',
      nationalId: '29001010100011',
      profileImageUrl: '',
      nationalIdFrontUrl: '',
      nationalIdBackUrl: '',
      paymentMethod: SubscriptionPaymentMethod.freePromotion,
      subscriptionCycle: '2026_H1',
      cycleStartDate: DateTime(2026, 1, 1),
      cycleEndDate: DateTime(2026, 6, 30),
      fee: 0,
      remainingMonths: 6,
      status: SubscriptionRequestStatus.pending,
      requestType: 'new_delegate',
      createdAt: DateTime(2026, 1, 1),
      paymentStatus: SubscriptionPaymentStatus.waived,
    );

void main() {
  const editable = true;

  test(
    'company supervisor of the same company can edit an active delegate',
    () {
      expect(
        canShowEditDelegateProfile(
          role: UserRole.admin,
          callerCompanyUID: 'coA',
          targetCompanyUID: 'coA',
          targetEditableStatus: editable,
        ),
        isTrue,
      );
    },
  );

  test('company supervisor of another company cannot edit', () {
    expect(
      canShowEditDelegateProfile(
        role: UserRole.admin,
        callerCompanyUID: 'coA',
        targetCompanyUID: 'coB',
        targetEditableStatus: editable,
      ),
      isFalse,
    );
  });

  test('super-admin and technical support can edit any company', () {
    expect(
      canShowEditDelegateProfile(
        role: UserRole.superAdmin,
        callerCompanyUID: '',
        targetCompanyUID: 'coA',
        targetEditableStatus: editable,
      ),
      isTrue,
    );
    expect(
      canShowEditDelegateProfile(
        role: UserRole.technicalSupport,
        callerCompanyUID: '',
        targetCompanyUID: 'coA',
        targetEditableStatus: editable,
      ),
      isTrue,
    );
  });

  test('HR, org-admin, accountant and marketing cannot edit', () {
    for (final role in [
      UserRole.hr,
      UserRole.organizationAdmin,
      UserRole.accountant,
      UserRole.marketing,
      UserRole.marketingPromotion,
    ]) {
      expect(
        canShowEditDelegateProfile(
          role: role,
          callerCompanyUID: 'coA',
          targetCompanyUID: 'coA',
          targetEditableStatus: editable,
        ),
        isFalse,
        reason: '$role',
      );
    }
  });

  test('inactive delegates are not editable', () {
    expect(
      canShowEditDelegateProfile(
        role: UserRole.superAdmin,
        callerCompanyUID: '',
        targetCompanyUID: 'coA',
        targetEditableStatus: false,
      ),
      isFalse,
    );
  });

  test('same-company supervisor can edit a pending new_delegate request', () {
    expect(
      canSupervisorEditSubscriptionRequest(
        _pendingNewDelegate(),
        role: UserRole.admin,
        callerCompanyUID: 'c1',
      ),
      isTrue,
    );
  });

  test('national-ID update requests are not editable from the profile screen', () {
    final req = _pendingNewDelegate().copyWith(requestType: 'update_national_id');
    expect(
      canSupervisorEditSubscriptionRequest(
        req,
        role: UserRole.admin,
        callerCompanyUID: 'c1',
      ),
      isFalse,
    );
  });

  test('HR cannot edit a pending subscription request profile', () {
    expect(
      canSupervisorEditSubscriptionRequest(
        _pendingNewDelegate(),
        role: UserRole.hr,
        callerCompanyUID: 'c1',
      ),
      isFalse,
    );
  });
}
