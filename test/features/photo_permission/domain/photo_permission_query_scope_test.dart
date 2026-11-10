import 'package:delegate_app/features/photo_permission/domain/photo_permission_query_scope.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('super-admin and tech list unfiltered', () {
    for (final role in [UserRole.superAdmin, UserRole.technicalSupport]) {
      final scope = PhotoPermissionQueryScope.forRole(
        role: role,
        organizationUID: 'o1',
        companyUID: 'c1',
      );
      expect(scope.isGlobalStaff, isTrue);
      expect(scope.organizationUID, isEmpty);
      expect(scope.companyUID, isEmpty);
      expect(scope.shouldQuery, isTrue);
    }
  });

  test('marketing and org-admin are scoped to their org', () {
    for (final role in [UserRole.marketingPromotion, UserRole.organizationAdmin, UserRole.marketing]) {
      final scope = PhotoPermissionQueryScope.forRole(
        role: role,
        organizationUID: 'o1',
        companyUID: '',
      );
      expect(scope.isGlobalStaff, isFalse);
      expect(scope.organizationUID, 'o1');
      expect(scope.companyUID, isEmpty);
      expect(scope.shouldQuery, isTrue);
    }
  });

  test('marketing without org or company must not query (spinner fix)', () {
    final scope = PhotoPermissionQueryScope.forRole(
      role: UserRole.marketingPromotion,
      organizationUID: '',
      companyUID: '',
    );
    expect(scope.shouldQuery, isFalse);
  });
}
