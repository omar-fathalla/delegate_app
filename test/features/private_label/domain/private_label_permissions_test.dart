import 'package:flutter_test/flutter_test.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_permissions.dart';

void main() {
  group('PrivateLabelPermissions Entity Tests', () {
    test('default empty permissions has hasAnyPermission == false', () {
      final perm = PrivateLabelPermissions.empty('user_123');

      expect(perm.userId, 'user_123');
      expect(perm.canCapture, isFalse);
      expect(perm.canViewReports, isFalse);
      expect(perm.canReviewAudit, isFalse);
      expect(perm.hasAnyPermission, isFalse);
    });

    test('hasAnyPermission is true when any flag is enabled', () {
      final captureOnly = const PrivateLabelPermissions(
        userId: 'u1',
        canCapture: true,
      );
      final reportOnly = const PrivateLabelPermissions(
        userId: 'u2',
        canViewReports: true,
      );
      final auditOnly = const PrivateLabelPermissions(
        userId: 'u3',
        canReviewAudit: true,
      );
      final allDisabled = const PrivateLabelPermissions(
        userId: 'u4',
      );

      expect(captureOnly.hasAnyPermission, isTrue);
      expect(reportOnly.hasAnyPermission, isTrue);
      expect(auditOnly.hasAnyPermission, isTrue);
      expect(allDisabled.hasAnyPermission, isFalse);
    });

    test('copyWith updates properties accurately', () {
      final original = const PrivateLabelPermissions(
        userId: 'u1',
        userName: 'Ahmed',
        canCapture: false,
        canViewReports: false,
        canReviewAudit: false,
      );

      final updated = original.copyWith(
        canCapture: true,
        canViewReports: true,
        updatedBy: 'admin_1',
        updatedByName: 'Omar SuperAdmin',
      );

      expect(updated.userId, 'u1');
      expect(updated.userName, 'Ahmed');
      expect(updated.canCapture, isTrue);
      expect(updated.canViewReports, isTrue);
      expect(updated.canReviewAudit, isFalse);
      expect(updated.updatedBy, 'admin_1');
      expect(updated.updatedByName, 'Omar SuperAdmin');
    });

    test('equatable props support value equality', () {
      final p1 = const PrivateLabelPermissions(
        userId: 'u1',
        userName: 'Same',
        canCapture: true,
      );
      final p2 = const PrivateLabelPermissions(
        userId: 'u1',
        userName: 'Same',
        canCapture: true,
      );
      final p3 = const PrivateLabelPermissions(
        userId: 'u1',
        userName: 'Same',
        canCapture: false,
      );

      expect(p1, equals(p2));
      expect(p1 == p3, isFalse);
    });
  });
}
