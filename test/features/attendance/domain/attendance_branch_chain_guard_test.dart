import 'package:delegate_app/core/attendance/attendance_branch_ref.dart';
import 'package:delegate_app/features/admin/domain/entities/branch.dart';
import 'package:delegate_app/features/attendance/domain/attendance_branch_chain_guard.dart';
import 'package:delegate_app/features/attendance/domain/branch_auto_locator.dart';
import 'package:flutter_test/flutter_test.dart';

/// TAS-333: two chains with a branch at the same location. The delegate is a
/// member of `tas112` only; `hr` is someone else's chain.
const _lat = 30.1001;
const _lng = 31.2001;

const _ownBranch = Branch(
  id: 'seed-fake-tas112-br-qr',
  branchName: 'Fake Branch QR',
  latitude: _lat,
  longitude: _lng,
  geofenceRadius: 300,
  organizationUID: 'seed-fake-tas112-org',
);

const _foreignBranch = Branch(
  id: 'seed-fake-br-alpha',
  branchName: 'Fake Branch Alpha',
  latitude: _lat,
  longitude: _lng,
  geofenceRadius: 100,
  organizationUID: 'seed-fake-hr-org',
);

typedef M = ({String org, String company});

double _zero(double a, double b, double c, double d) => 0;

void main() {
  const current = 'seed-fake-tas112-org';
  const members = {'seed-fake-tas112-org'};

  group('QR mode: the scanned branch is the one recorded (TAS-333)', () {
    test('own chain QR passes and keeps the scanned branch as is', () {
      final ref = AttendanceBranchRef.fromQrMap({
        'type': 'attendance',
        'branch': 'Fake Branch QR',
        'branchId': 'seed-fake-tas112-br-qr',
        'organizationUID': 'seed-fake-tas112-org',
      }, delegateOrganizationUID: current);
      expect(
        checkBranchChain(
          branchOrganizationUID: ref.branchOrganizationUID,
          currentOrgId: current,
          memberOrgIds: members,
        ),
        BranchChainCheck.ok,
      );
      // Nothing in the flow swaps it for the same-location branch.
      expect(ref.branchId, 'seed-fake-tas112-br-qr');
      expect(ref.toCheckInFields(), {
        'branchName': 'Fake Branch QR',
        'branchId': 'seed-fake-tas112-br-qr',
        'branchOrganizationUID': 'seed-fake-tas112-org',
      });
    });

    test('QR of another chain at the same place is refused', () {
      final ref = AttendanceBranchRef.fromQrMap({
        'type': 'attendance',
        'branch': 'Fake Branch Alpha',
        'branchId': 'seed-fake-br-alpha',
        'organizationUID': 'seed-fake-hr-org',
      }, delegateOrganizationUID: current);
      expect(
        checkBranchChain(
          branchOrganizationUID: ref.branchOrganizationUID,
          currentOrgId: current,
          memberOrgIds: members,
        ),
        BranchChainCheck.notMember,
      );
    });

    test('QR of the delegate\'s other chain asks to switch first', () {
      expect(
        checkBranchChain(
          branchOrganizationUID: 'seed-fake-hr-org',
          currentOrgId: current,
          memberOrgIds: {...members, 'seed-fake-hr-org'},
        ),
        BranchChainCheck.otherOwnChain,
      );
    });

    test('legacy name-only QR resolves in the open chain', () {
      final ref = AttendanceBranchRef.legacyNameOnly(
        branchName: 'Fake Branch QR',
        delegateOrganizationUID: current,
      );
      expect(
        checkBranchChain(
          branchOrganizationUID: ref.branchOrganizationUID,
          currentOrgId: current,
          memberOrgIds: members,
        ),
        BranchChainCheck.ok,
      );
      expect(
        checkBranchChain(
          branchOrganizationUID: '',
          currentOrgId: current,
          memberOrgIds: members,
        ),
        BranchChainCheck.ok,
      );
    });
  });

  group('geofence mode: only the delegate\'s own chains (TAS-333)', () {
    test('keepMemberChainBranches drops the other chain\'s branch', () {
      final kept = keepMemberChainBranches(const [
        _foreignBranch,
        _ownBranch,
      ], members);
      expect(kept, [_ownBranch]);
    });

    test('auto-detection picks the own branch, never the foreign one', () {
      final result = locateBranchAcrossChains<M>(
        latitude: _lat,
        longitude: _lng,
        branches: const [_foreignBranch, _ownBranch],
        currentOrgId: current,
        memberships: const [(org: 'seed-fake-tas112-org', company: 'co')],
        orgIdOf: (m) => m.org,
        distance: _zero,
      );
      expect(result.outcome, AutoBranchOutcome.currentChain);
      expect(result.branch, _ownBranch);
      // Radius comes from the picked branch (300 + 50), not Alpha's 150.
      expect(allowedGeofenceRadius(result.branch!), 350);
    });

    test('only a foreign branch nearby: no match and no chain switch', () {
      final result = locateBranchAcrossChains<M>(
        latitude: _lat,
        longitude: _lng,
        branches: const [_foreignBranch],
        currentOrgId: current,
        memberships: const [(org: 'seed-fake-tas112-org', company: 'co')],
        orgIdOf: (m) => m.org,
        distance: _zero,
      );
      expect(result.outcome, AutoBranchOutcome.none);
      expect(keepMemberChainBranches(const [_foreignBranch], members), isEmpty);
    });

    test('a branch picked in geofence mode passes the chain check', () {
      final ref = AttendanceBranchRef.fromBranch(
        _ownBranch,
        fallbackOrganizationUID: current,
      );
      expect(
        checkBranchChain(
          branchOrganizationUID: ref.branchOrganizationUID,
          currentOrgId: current,
          memberOrgIds: members,
        ),
        BranchChainCheck.ok,
      );
      final foreign = AttendanceBranchRef.fromBranch(
        _foreignBranch,
        fallbackOrganizationUID: current,
      );
      expect(
        checkBranchChain(
          branchOrganizationUID: foreign.branchOrganizationUID,
          currentOrgId: current,
          memberOrgIds: members,
        ),
        BranchChainCheck.notMember,
      );
    });
  });
}
