import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/tasks/presentation/task_details_access.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('staff who create tasks open the details screen as admin', () {
    const staff = [
      UserRole.admin,
      UserRole.organizationAdmin,
      UserRole.superAdmin,
      UserRole.technicalSupport,
      UserRole.branchesMarketingManager,
      UserRole.marketingPromotion,
    ];
    for (final role in staff) {
      expect(taskNotificationOpensAsAdmin(role), isTrue, reason: role.name);
    }
  });

  test('delegates, branch marketing, hr and accountants open it as recipients', () {
    const recipients = [
      UserRole.delegate,
      UserRole.marketing,
      UserRole.hr,
      UserRole.accountant,
    ];
    for (final role in recipients) {
      expect(taskNotificationOpensAsAdmin(role), isFalse, reason: role.name);
    }
  });
}
