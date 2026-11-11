import 'package:delegate_app/features/admin/domain/entities/delegate_profile_edit_access.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
