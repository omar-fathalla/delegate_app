import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/org/org_scope.dart';
import 'package:delegate_app/features/marketing_search/presentation/bloc/marketing_search_bloc.dart';
import 'package:delegate_app/features/notifications/presentation/pages/send_notification_screen.dart';
import 'package:delegate_app/features/photo_permission/presentation/bloc/photo_permission_bloc.dart';
import 'package:delegate_app/features/photo_permission/presentation/pages/super_admin_permissions_report_screen.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/tasks/domain/task_assignee_label.dart';
import 'package:flutter_test/flutter_test.dart';

Delegate _user(UserRole role, {String org = 'org-a'}) => Delegate(
      uid: 'u1',
      firstName: 'أحمد',
      middleName: '',
      lastName: 'علي',
      fullName: 'أحمد علي',
      nationalityID: '29001011234567',
      motherName: '',
      city: '',
      phoneNumber: '01000000000',
      gender: DelegateGender.male,
      position: DelegatePosition.promoter,
      birthDate: DateTime(1990, 1, 1),
      organizationUID: org,
      organizationName: 'سلسلة',
      companyUID: '',
      companyName: '',
      status: DelegateStatus.active,
      delegatePublicId: 'D-1',
      allReceiptCodes: const [],
      createdAt: DateTime(2024, 1, 1),
      createdBy: 'seed',
      hasPendingUpdate: false,
      isDeductedFromCompany: false,
      isPrinted: false,
      isProfileComplete: true,
      numberOfDocuments: 0,
      paymentAmount: 0,
      version: 1,
      documents: const [],
      role: role,
    );

void main() {
  group('TAS-267 org scope', () {
    test('global staff are not scoped', () {
      expect(orgScopeFor(_user(UserRole.superAdmin)), isNull);
      expect(orgScopeFor(_user(UserRole.technicalSupport)), isNull);
    });

    test('marketing roles are scoped to their own org', () {
      for (final r in [
        UserRole.marketing,
        UserRole.branchesMarketingManager,
        UserRole.marketingPromotion,
        UserRole.organizationAdmin,
      ]) {
        expect(orgScopeFor(_user(r)), 'org-a', reason: r.name);
      }
    });

    test('non-global user without org matches nothing', () {
      expect(orgScopeFor(_user(UserRole.marketing, org: '')), '');
      expect(orgScopeFor(_user(UserRole.marketing, org: 'all')), '');
      expect(branchBelongsToOrg({'organizationUID': ''}, ''), isFalse);
    });

    test('branch org match uses organizationUID or organizationId', () {
      expect(branchBelongsToOrg({'organizationUID': 'org-a'}, 'org-a'), isTrue);
      expect(branchBelongsToOrg({'organizationId': 'org-a'}, 'org-a'), isTrue);
      expect(branchBelongsToOrg({'organizationUID': 'org-b'}, 'org-a'), isFalse);
      expect(branchBelongsToOrg(const {}, 'org-a'), isFalse);
    });
  });

  group('TAS-268 send error message', () {
    test('permission-denied is a clear Arabic message', () {
      final msg = sendNotificationErrorMessage(
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
      );
      expect(msg, contains('صلاحية'));
      expect(msg, isNot(contains('permission')));
    });

    test('unknown errors never leak the raw exception', () {
      final msg = sendNotificationErrorMessage(Exception('boom'));
      expect(msg, isNot(contains('boom')));
    });
  });

  group('TAS-270 task assignee label', () {
    test('sector keys map to Arabic labels', () {
      expect(
        taskAssigneeLabel(
          assignedTo: 'all_marketing_promotion',
          assignedToName: 'all_marketing_promotion',
        ),
        'قطاع تسويق العروض',
      );
      expect(
        taskAssigneeLabel(assignedTo: 'all_branch_marketing', assignedToName: ''),
        'قطاع تسويق الفروع',
      );
    });

    test('a person name is shown as-is', () {
      expect(
        taskAssigneeLabel(assignedTo: 'uid-1', assignedToName: 'محمد'),
        'محمد',
      );
    });
  });

  group('TAS-270 phone detection in delegate search', () {
    test('digits are a phone number', () {
      expect(looksLikePhoneNumber('01012345678'), isTrue);
      expect(looksLikePhoneNumber('+20 101 234 5678'), isTrue);
    });

    test('names and short numbers are not', () {
      expect(looksLikePhoneNumber('أحمد'), isFalse);
      expect(looksLikePhoneNumber('123'), isFalse);
    });
  });

  group('TAS-270 approve permission message', () {
    test('says waiting for supervisor when not enabled', () {
      final msg = approvePermissionMessage(
        status: 'approved',
        isSupervisorEnabled: false,
      );
      expect(msg, contains('انتظار'));
      expect(msg, isNot(contains('وتفعيله بنجاح')));
    });

    test('says active when enabled', () {
      expect(
        approvePermissionMessage(status: 'approved', isSupervisorEnabled: true),
        contains('وتفعيله بنجاح'),
      );
    });
  });

  test('TAS-266: photo permissions report is scoped for non-global staff', () {
    final bmm = _user(UserRole.branchesMarketingManager, org: 'org-f');
    expect(reportOrgScope(bmm), 'org-f');
    expect(reportCompanyScope(bmm), '');
    final sa = _user(UserRole.superAdmin, org: 'org-f');
    expect(reportOrgScope(sa), '');
    expect(reportCompanyScope(sa), '');
  });
}
