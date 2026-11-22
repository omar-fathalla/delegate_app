import 'package:delegate_app/features/admin/domain/entities/branch.dart';
import 'package:delegate_app/features/attendance/domain/branch_auto_locator.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake memberships: (orgId, companyId).
typedef M = ({String org, String company});

/// 1 degree of latitude = 1000 m in these tests (flat fake distance).
double _flat(double lat1, double lng1, double lat2, double lng2) {
  final dLat = (lat1 - lat2) * 1000;
  final dLng = (lng1 - lng2) * 1000;
  return dLat.abs() > dLng.abs() ? dLat.abs() : dLng.abs();
}

Branch _b(String id, String org, double lat, {double radius = 100}) => Branch(
      id: id,
      branchName: 'فرع $id',
      latitude: lat,
      longitude: 0.001, // non-zero so it counts as having coordinates
      geofenceRadius: radius,
      organizationUID: org,
    );

AutoBranchResult<M> _locate({
  required double lat,
  required List<Branch> branches,
  String current = 'zahran',
  List<M> memberships = const [
    (org: 'zahran', company: 'c1'),
    (org: 'gomla', company: 'c1'),
  ],
  Set<String>? geofenceOrgIds,
}) =>
    locateBranchAcrossChains<M>(
      latitude: lat,
      longitude: 0.001,
      branches: branches,
      currentOrgId: current,
      memberships: memberships,
      orgIdOf: (m) => m.org,
      geofenceOrgIds: geofenceOrgIds,
      distance: _flat,
    );

void main() {
  group('allowedGeofenceRadius', () {
    test('adds 50 m of slack, or 150 m when the radius is missing', () {
      expect(allowedGeofenceRadius(_b('a', 'x', 0, radius: 100)), 150);
      expect(allowedGeofenceRadius(_b('a', 'x', 0, radius: 0)), 150);
      expect(allowedGeofenceRadius(_b('a', 'x', 0, radius: 300)), 350);
    });
  });

  group('locateBranchAcrossChains', () {
    test('inside a branch of the open chain → currentChain', () {
      final r = _locate(lat: 1.0, branches: [_b('smouha', 'zahran', 1.05)]);
      expect(r.outcome, AutoBranchOutcome.currentChain);
      expect(r.branch!.id, 'smouha');
      expect(r.distance, closeTo(50, 0.01));
    });

    test('inside a branch of another chain → switchChain with that membership',
        () {
      final r = _locate(lat: 2.0, branches: [
        _b('smouha', 'zahran', 1.0),
        _b('miami', 'gomla', 2.1),
      ]);
      expect(r.outcome, AutoBranchOutcome.switchChain);
      expect(r.branch!.id, 'miami');
      expect(r.memberships, [(org: 'gomla', company: 'c1')]);
    });

    test('overlapping branches: the open chain wins even if farther', () {
      final r = _locate(lat: 3.0, branches: [
        _b('mall-gomla', 'gomla', 3.01),
        _b('mall-zahran', 'zahran', 3.12),
      ]);
      expect(r.outcome, AutoBranchOutcome.currentChain);
      expect(r.branch!.id, 'mall-zahran');
    });

    test('two other chains in range: the nearest one is chosen', () {
      final r = _locate(
        lat: 4.0,
        memberships: const [
          (org: 'zahran', company: 'c1'),
          (org: 'gomla', company: 'c1'),
          (org: 'kazyon', company: 'c1'),
        ],
        branches: [
          _b('far', 'gomla', 4.12),
          _b('near', 'kazyon', 4.03),
        ],
      );
      expect(r.outcome, AutoBranchOutcome.switchChain);
      expect(r.branch!.id, 'near');
    });

    test('not inside any branch → none', () {
      final r = _locate(lat: 5.0, branches: [
        _b('smouha', 'zahran', 5.5),
        _b('miami', 'gomla', 6.0),
      ]);
      expect(r.outcome, AutoBranchOutcome.none);
      expect(r.branch, isNull);
    });

    test('branches of chains the delegate is not in are ignored', () {
      final r = _locate(lat: 7.0, branches: [_b('other', 'carrefour', 7.0)]);
      expect(r.outcome, AutoBranchOutcome.none);
    });

    test('several companies in the matched chain → pickCompany', () {
      final r = _locate(
        lat: 8.0,
        memberships: const [
          (org: 'zahran', company: 'c1'),
          (org: 'gomla', company: 'c1'),
          (org: 'gomla', company: 'c2'),
        ],
        branches: [_b('miami', 'gomla', 8.0)],
      );
      expect(r.outcome, AutoBranchOutcome.pickCompany);
      expect(r.memberships.length, 2);
    });

    test('chains that are not in geofence mode are skipped', () {
      final r = _locate(
        lat: 9.0,
        branches: [_b('miami', 'gomla', 9.0)],
        geofenceOrgIds: const {'zahran'},
      );
      expect(r.outcome, AutoBranchOutcome.none);
    });

    test('branches without coordinates are skipped', () {
      final stub = Branch(
        id: 'stub',
        branchName: 'stub',
        latitude: 0,
        longitude: 0,
        geofenceRadius: 100,
        organizationUID: 'gomla',
      );
      final r = locateBranchAcrossChains<M>(
        latitude: 0,
        longitude: 0,
        branches: [stub],
        currentOrgId: 'zahran',
        memberships: const [(org: 'gomla', company: 'c1')],
        orgIdOf: (m) => m.org,
        distance: _flat,
      );
      expect(r.outcome, AutoBranchOutcome.none);
    });
  });
}
