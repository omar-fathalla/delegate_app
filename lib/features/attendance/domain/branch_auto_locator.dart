import 'package:delegate_app/features/admin/domain/entities/branch.dart';
import 'package:geolocator/geolocator.dart';

/// Distance between two points in meters.
typedef DistanceFn = double Function(
  double lat1,
  double lng1,
  double lat2,
  double lng2,
);

/// Radius (meters) inside which the delegate counts as "at" [branch].
/// Same rule as the check-in screen: the branch radius plus 50 m of GPS
/// slack, or 150 m when the branch has no radius.
double allowedGeofenceRadius(Branch branch) =>
    branch.geofenceRadius > 0 ? branch.geofenceRadius + 50.0 : 150.0;

bool _hasCoordinates(Branch b) => !(b.latitude == 0.0 && b.longitude == 0.0);

/// What the attendance screen should do after looking for the branch the
/// delegate is standing in, across every chain they belong to (TAS-245).
enum AutoBranchOutcome {
  /// Inside a branch of the chain that is already open.
  currentChain,

  /// Inside a branch of another chain with exactly one membership:
  /// switch to [AutoBranchResult.memberships].first.
  switchChain,

  /// Inside a branch of another chain, but the delegate has several
  /// memberships (companies) in it. Branches carry no company, so the
  /// delegate has to pick.
  pickCompany,

  /// Not inside any branch of any of their chains.
  none,
}

class AutoBranchResult<T> {
  final AutoBranchOutcome outcome;
  final Branch? branch;
  final double? distance;

  /// Memberships in the matched branch's chain (empty for [currentChain]
  /// and [none]).
  final List<T> memberships;

  const AutoBranchResult({
    required this.outcome,
    this.branch,
    this.distance,
    this.memberships = const [],
  });

  const AutoBranchResult.none() : this(outcome: AutoBranchOutcome.none);
}

/// Finds the branch the delegate is standing in among [branches] of every
/// chain in [memberships].
///
/// - A match in [currentOrgId] wins, so overlapping geofences (a mall with
///   two chains) never cause a needless switch.
/// - Otherwise the nearest matching branch of another chain is chosen.
/// - Branches of chains not in [memberships], or not in [geofenceOrgIds]
///   when it is given, are ignored.
AutoBranchResult<T> locateBranchAcrossChains<T>({
  required double latitude,
  required double longitude,
  required Iterable<Branch> branches,
  required String currentOrgId,
  required List<T> memberships,
  required String Function(T membership) orgIdOf,
  Set<String>? geofenceOrgIds,
  DistanceFn distance = Geolocator.distanceBetween,
}) {
  final memberOrgs = memberships.map(orgIdOf).where((o) => o.isNotEmpty).toSet();
  memberOrgs.add(currentOrgId);

  Branch? bestCurrent;
  double bestCurrentDist = double.infinity;
  Branch? bestOther;
  double bestOtherDist = double.infinity;

  for (final b in branches) {
    final org = (b.organizationUID ?? '').trim();
    if (org.isEmpty || !memberOrgs.contains(org)) continue;
    if (geofenceOrgIds != null &&
        org != currentOrgId &&
        !geofenceOrgIds.contains(org)) {
      continue;
    }
    if (!_hasCoordinates(b)) continue;

    final d = distance(latitude, longitude, b.latitude, b.longitude);
    if (d > allowedGeofenceRadius(b)) continue;

    if (org == currentOrgId) {
      if (d < bestCurrentDist) {
        bestCurrentDist = d;
        bestCurrent = b;
      }
    } else if (d < bestOtherDist) {
      bestOtherDist = d;
      bestOther = b;
    }
  }

  if (bestCurrent != null) {
    return AutoBranchResult(
      outcome: AutoBranchOutcome.currentChain,
      branch: bestCurrent,
      distance: bestCurrentDist,
    );
  }
  if (bestOther == null) return AutoBranchResult<T>.none();

  final org = bestOther.organizationUID!.trim();
  final inChain = memberships.where((m) => orgIdOf(m) == org).toList();
  return AutoBranchResult(
    outcome: inChain.length == 1
        ? AutoBranchOutcome.switchChain
        : AutoBranchOutcome.pickCompany,
    branch: bestOther,
    distance: bestOtherDist,
    memberships: inChain,
  );
}
