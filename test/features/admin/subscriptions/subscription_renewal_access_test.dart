import 'package:delegate_app/features/admin/domain/entities/subscription_renewal.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('canCreateSubscriptionRenewal', () {
    test('supervisors and company admins (UserRole.admin) may create renewals', () {
      expect(
        canCreateSubscriptionRenewal(role: UserRole.admin, companyUID: 'co_dev_test'),
        isTrue,
      );
    });

    test('HR may create renewals for their company', () {
      expect(
        canCreateSubscriptionRenewal(role: UserRole.hr, companyUID: 'co_dev_test'),
        isTrue,
      );
    });

    test('org-admins may create renewals only when companyUID is set', () {
      expect(
        canCreateSubscriptionRenewal(
          role: UserRole.organizationAdmin,
          companyUID: 'co_dev_test',
        ),
        isTrue,
      );
      expect(
        canCreateSubscriptionRenewal(role: UserRole.organizationAdmin, companyUID: ''),
        isFalse,
      );
      expect(
        canCreateSubscriptionRenewal(role: UserRole.organizationAdmin, companyUID: '  '),
        isFalse,
      );
    });

    test('other roles and empty company are fail-closed', () {
      for (final role in [
        UserRole.delegate,
        UserRole.superAdmin,
        UserRole.technicalSupport,
        UserRole.marketing,
        UserRole.marketingPromotion,
        UserRole.branchesMarketingManager,
        UserRole.accountant,
      ]) {
        expect(
          canCreateSubscriptionRenewal(role: role, companyUID: 'co_dev_test'),
          isFalse,
          reason: role.toString(),
        );
      }
      expect(
        canCreateSubscriptionRenewal(role: UserRole.admin, companyUID: ''),
        isFalse,
      );
      expect(
        canCreateSubscriptionRenewal(role: UserRole.hr, companyUID: ''),
        isFalse,
      );
    });
  });
}
