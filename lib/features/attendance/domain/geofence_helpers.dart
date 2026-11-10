import 'package:delegate_app/features/admin/domain/entities/branch.dart';

/// How to phrase the "outside the geofence" message.
enum GeofenceOutsideKind { atBranch, branchOnly, distanceOnly, noDetails }

GeofenceOutsideKind classifyGeofenceOutside({
  String? branchName,
  double? distanceMeters,
}) {
  final hasName = branchName != null && branchName.trim().isNotEmpty;
  final hasDist = distanceMeters != null && distanceMeters.isFinite;
  if (hasName && hasDist) return GeofenceOutsideKind.atBranch;
  if (hasName) return GeofenceOutsideKind.branchOnly;
  if (hasDist) return GeofenceOutsideKind.distanceOnly;
  return GeofenceOutsideKind.noDetails;
}

/// Merge nested org branches with root `branches` docs. A stub nested
/// doc (no coordinates) must not hide real root branches for the same org.
List<Branch> mergeOrgBranches(List<Branch> nested, List<Branch> root) {
  final out = <Branch>[];
  final seenIds = <String>{};
  final seenNames = <String>{};

  void add(Branch b) {
    final id = b.id.trim();
    final name = b.branchName.trim().toLowerCase();
    if (id.isNotEmpty && seenIds.contains(id)) {
      // Prefer the copy that has coordinates if we already stored a stub.
      final idx = out.indexWhere((e) => e.id.trim() == id);
      if (idx >= 0 &&
          out[idx].latitude == 0 &&
          out[idx].longitude == 0 &&
          (b.latitude != 0 || b.longitude != 0)) {
        out[idx] = b;
      }
      return;
    }
    if (id.isEmpty && name.isNotEmpty && seenNames.contains(name)) return;
    if (id.isNotEmpty) seenIds.add(id);
    if (name.isNotEmpty) seenNames.add(name);
    out.add(b);
  }

  for (final b in nested) {
    add(b);
  }
  for (final b in root) {
    add(b);
  }
  return out;
}
