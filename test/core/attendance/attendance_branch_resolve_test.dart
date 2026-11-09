import 'package:delegate_app/core/attendance/attendance_branch_resolve.dart';
import 'package:delegate_app/features/admin/domain/entities/branch.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('lookupBranchForAttendanceLog', () {
    late Map<String, Branch> map;

    setUp(() {
      map = {};
      registerBranchInLookupMap(
        map,
        const Branch(
          id: 'id_gomla_madinaty',
          branchName: 'مدينتى',
          latitude: 30.1,
          longitude: 31.2,
          geofenceRadius: 100,
          organizationUID: 'org_gomla',
        ),
      );
      registerBranchInLookupMap(
        map,
        const Branch(
          id: 'id_fath_madinaty',
          branchName: 'مدينتى',
          latitude: 30.2,
          longitude: 31.3,
          geofenceRadius: 100,
          organizationUID: 'org_fathalla',
        ),
      );
    });

    test('resolves by branchId on log', () {
      final branch = lookupBranchForAttendanceLog(
        branchesByName: map,
        log: {
          'branchId': 'id_gomla_madinaty',
          'branchName': 'مدينتى',
          'branchOrganizationUID': 'org_gomla',
        },
      );
      expect(branch?.id, 'id_gomla_madinaty');
      expect(branch?.organizationUID, 'org_gomla');
    });

    test('legacy log without branchId uses org-scoped name', () {
      final branch = lookupBranchForAttendanceLog(
        branchesByName: map,
        log: {
          'branchName': 'مدينتى',
          'organizationId': 'org_fathalla',
        },
      );
      expect(branch?.id, 'id_fath_madinaty');
    });
  });
}
