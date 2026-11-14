import 'package:delegate_app/core/attendance/attendance_branch_ref.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('attendanceSameBranch', () {
    test('matches duplicate names across chains by branchId + org', () {
      final fathalla = AttendanceBranchRef(
        branchId: 'b1',
        branchOrganizationUID: 'org_fathalla',
        branchName: 'مدينتى',
      );
      final gomla = AttendanceBranchRef(
        branchId: 'b2',
        branchOrganizationUID: 'org_gomla',
        branchName: 'مدينتى',
      );

      expect(attendanceSameBranch(fathalla, gomla), isFalse);

      final sameChain = AttendanceBranchRef(
        branchId: 'b1',
        branchOrganizationUID: 'org_fathalla',
        branchName: 'مدينتى',
      );
      expect(attendanceSameBranch(fathalla, sameChain), isTrue);
    });

    test('legacy logs without branchId match name within same org', () {
      final legacy = AttendanceBranchRef.legacyNameOnly(
        branchName: 'سموحة',
        delegateOrganizationUID: 'org1',
      );
      final incoming = AttendanceBranchRef(
        branchId: null,
        branchOrganizationUID: 'org1',
        branchName: 'سموحة',
      );
      expect(attendanceSameBranch(legacy, incoming), isTrue);
    });

    test('legacy QR name-only does not cross organizations', () {
      final qrLegacy = AttendanceBranchRef.legacyNameOnly(
        branchName: 'التجمع الخامس',
        delegateOrganizationUID: 'org_delegate',
      );
      final otherOrg = AttendanceBranchRef(
        branchId: 'x',
        branchOrganizationUID: 'org_other',
        branchName: 'التجمع الخامس',
      );
      expect(attendanceSameBranch(qrLegacy, otherOrg), isFalse);
    });

    test('fromQrMap prefers branchId when present', () {
      final ref = AttendanceBranchRef.fromQrMap(
        {
          'type': 'attendance',
          'branch': 'شيراتون',
          'branchId': 'branch_sheraton_1',
          'organizationUID': 'org_chain_a',
        },
        delegateOrganizationUID: 'fallback_org',
      );
      expect(ref.branchId, 'branch_sheraton_1');
      expect(ref.branchOrganizationUID, 'org_chain_a');
      expect(ref.branchName, 'شيراتون');
    });
  });
}
