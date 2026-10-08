import 'package:flutter_test/flutter_test.dart';
import 'package:delegate_app/features/private_label/data/models/private_label_permissions_model.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_permissions.dart';

void main() {
  group('PrivateLabelPermissionsModel Tests', () {
    test('fromMap parses map data accurately', () {
      final map = {
        'userName': 'Mohamed Ali',
        'phoneNumber': '01012345678',
        'userRole': 'marketingPromotion',
        'organizationUID': 'org_123',
        'organizationName': 'Fathalla Org',
        'companyUID': 'comp_456',
        'companyName': 'Fathalla Market',
        'canCapture': true,
        'canViewReports': false,
        'canReviewAudit': true,
        'updatedAt': '2026-10-08T09:00:00.000Z',
        'updatedBy': 'admin_999',
        'updatedByName': 'SuperAdmin Omar',
      };

      final model = PrivateLabelPermissionsModel.fromMap('user_abc', map);

      expect(model.userId, 'user_abc');
      expect(model.userName, 'Mohamed Ali');
      expect(model.phoneNumber, '01012345678');
      expect(model.userRole, 'marketingPromotion');
      expect(model.organizationUID, 'org_123');
      expect(model.organizationName, 'Fathalla Org');
      expect(model.companyUID, 'comp_456');
      expect(model.companyName, 'Fathalla Market');
      expect(model.canCapture, isTrue);
      expect(model.canViewReports, isFalse);
      expect(model.canReviewAudit, isTrue);
      expect(model.updatedBy, 'admin_999');
      expect(model.updatedByName, 'SuperAdmin Omar');
      expect(model.updatedAt, isNotNull);
    });

    test('fromMap handles alternative legacy keys (displayName, name, phone, canAccessReport, canAccessAudit)', () {
      final map = {
        'displayName': 'Alternative Name',
        'phone': '01200000000',
        'role': 'marketing_promotion',
        'organizationId': 'org_alt',
        'companyId': 'comp_alt',
        'canAccessReport': true,
        'canAccessAudit': true,
      };

      final model = PrivateLabelPermissionsModel.fromMap('user_legacy', map);

      expect(model.userId, 'user_legacy');
      expect(model.userName, 'Alternative Name');
      expect(model.phoneNumber, '01200000000');
      expect(model.userRole, 'marketing_promotion');
      expect(model.organizationUID, 'org_alt');
      expect(model.companyUID, 'comp_alt');
      expect(model.canCapture, isFalse);
      expect(model.canViewReports, isTrue);
      expect(model.canReviewAudit, isTrue);
    });

    test('toMap converts model into valid map payload', () {
      const model = PrivateLabelPermissionsModel(
        userId: 'u_test',
        userName: 'Test User',
        phoneNumber: '01111111111',
        userRole: 'marketingPromotion',
        organizationUID: 'org_1',
        organizationName: 'Org 1',
        companyUID: 'comp_1',
        companyName: 'Comp 1',
        canCapture: true,
        canViewReports: true,
        canReviewAudit: false,
        updatedBy: 'admin_test',
        updatedByName: 'Admin Test',
      );

      final map = model.toMap();

      expect(map['userId'], 'u_test');
      expect(map['userName'], 'Test User');
      expect(map['phoneNumber'], '01111111111');
      expect(map['userRole'], 'marketingPromotion');
      expect(map['organizationUID'], 'org_1');
      expect(map['organizationName'], 'Org 1');
      expect(map['companyUID'], 'comp_1');
      expect(map['companyName'], 'Comp 1');
      expect(map['canCapture'], isTrue);
      expect(map['canViewReports'], isTrue);
      expect(map['canReviewAudit'], isFalse);
      expect(map['updatedBy'], 'admin_test');
      expect(map['updatedByName'], 'Admin Test');
      expect(map.containsKey('updatedAt'), isTrue);
    });

    test('fromEntity converts entity to model seamlessly', () {
      final entity = const PrivateLabelPermissions(
        userId: 'e_1',
        userName: 'Entity Name',
        canCapture: true,
        canViewReports: true,
        canReviewAudit: true,
      );

      final model = PrivateLabelPermissionsModel.fromEntity(entity);

      expect(model.userId, entity.userId);
      expect(model.userName, entity.userName);
      expect(model.canCapture, entity.canCapture);
      expect(model.canViewReports, entity.canViewReports);
      expect(model.canReviewAudit, entity.canReviewAudit);
    });
  });
}
