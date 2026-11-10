import 'package:delegate_app/features/admin/domain/entities/branch.dart';
import 'package:delegate_app/features/attendance/domain/geofence_helpers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('classifyGeofenceOutside', () {
    test('uses branch and distance when both are present', () {
      expect(
        classifyGeofenceOutside(branchName: 'فرع تجريبي DEV', distanceMeters: 420),
        GeofenceOutsideKind.atBranch,
      );
    });

    test('hides distance when it is null or non-finite', () {
      expect(
        classifyGeofenceOutside(branchName: 'فرع تجريبي DEV', distanceMeters: null),
        GeofenceOutsideKind.branchOnly,
      );
      expect(
        classifyGeofenceOutside(branchName: 'فرع تجريبي DEV', distanceMeters: double.infinity),
        GeofenceOutsideKind.branchOnly,
      );
    });

    test('uses distance only when the name is empty', () {
      expect(
        classifyGeofenceOutside(branchName: '  ', distanceMeters: 12),
        GeofenceOutsideKind.distanceOnly,
      );
    });

    test('falls back when both are missing', () {
      expect(
        classifyGeofenceOutside(branchName: null, distanceMeters: null),
        GeofenceOutsideKind.noDetails,
      );
    });
  });

  group('mergeOrgBranches', () {
    const stub = Branch(
      id: 'br_dev_test',
      branchName: 'فرع تجريبي DEV',
      latitude: 0,
      longitude: 0,
      geofenceRadius: 100,
    );
    const rooted = Branch(
      id: 'br_dev_perf_1',
      branchName: 'فرع تجريبي DEV المعادي',
      latitude: 30.06,
      longitude: 31.26,
      geofenceRadius: 100,
    );
    const stubWithCoords = Branch(
      id: 'br_dev_test',
      branchName: 'فرع تجريبي DEV',
      latitude: 30.05,
      longitude: 31.25,
      geofenceRadius: 100,
    );

    test('keeps root branches even when a nested stub already exists', () {
      final merged = mergeOrgBranches([stub], [rooted]);
      expect(merged, hasLength(2));
      expect(merged.any((b) => b.id == 'br_dev_perf_1' && b.latitude != 0), isTrue);
    });

    test('replaces a zero-coordinate stub with the geo-enabled copy of the same id', () {
      final merged = mergeOrgBranches([stub], [stubWithCoords]);
      expect(merged, hasLength(1));
      expect(merged.single.latitude, 30.05);
    });
  });
}
