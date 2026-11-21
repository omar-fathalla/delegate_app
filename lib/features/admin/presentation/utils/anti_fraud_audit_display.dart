import 'package:geolocator/geolocator.dart';

/// Display helpers for the anti-fraud audit screen (TAS-79).
///
/// They only *read* the log item and never write back: the screen used to
/// "repair" `branchName` / `branchUID` / `companyName` on the
/// security_audit_logs doc as soon as a row was rendered, so opening the
/// screen rewrote audit evidence. Any data repair must be an explicit admin
/// action or a server script, not a side effect of viewing.

const String kUnknownAuditBranch = 'غير محدد';

/// The branch to show for an audit log [item]:
/// 1. its stored `branchName` (unless it is the "unknown" placeholder),
/// 2. the name of the branch whose id is `branchUID`,
/// 3. the closest branch to the item's `latitude` / `longitude`,
/// 4. [kUnknownAuditBranch].
///
/// [branches] entries carry `id`, `name`, `latitude`, `longitude`.
/// [distance] is injectable for tests (defaults to Geolocator).
String resolveAuditBranchName(
  Map<String, dynamic> item,
  List<Map<String, dynamic>> branches, {
  double Function(double lat1, double lng1, double lat2, double lng2)? distance,
}) {
  final directBranch = (item['branchName'] as String?)?.trim() ?? '';
  if (directBranch.isNotEmpty && directBranch != kUnknownAuditBranch) {
    return directBranch;
  }

  final branchUid = (item['branchUID'] as String?)?.trim() ?? '';
  if (branchUid.isNotEmpty) {
    for (final b in branches) {
      if (b['id'] == branchUid) {
        final name = (b['name'] as String?)?.trim() ?? '';
        if (name.isNotEmpty) return name;
      }
    }
  }

  final lat = (item['latitude'] as num?)?.toDouble();
  final lng = (item['longitude'] as num?)?.toDouble();
  if (lat != null && lng != null) {
    final measure = distance ?? Geolocator.distanceBetween;
    var best = double.infinity;
    var bestName = '';
    for (final b in branches) {
      final bLat = (b['latitude'] as num?)?.toDouble();
      final bLng = (b['longitude'] as num?)?.toDouble();
      final name = (b['name'] as String?)?.trim() ?? '';
      if (bLat == null || bLng == null || name.isEmpty) continue;
      final d = measure(lat, lng, bLat, bLng);
      if (d < best) {
        best = d;
        bestName = name;
      }
    }
    if (bestName.isNotEmpty) return bestName;
  }

  return kUnknownAuditBranch;
}

/// The official company name for [item] from [companiesById] (doc id →
/// name), falling back to the name stored on the item.
String resolveAuditCompanyName(
  Map<String, dynamic> item,
  Map<String, String> companiesById,
) {
  final compUid = (item['companyUID'] as String?)?.trim() ?? '';
  final official = companiesById[compUid];
  if (compUid.isNotEmpty && official != null && official.isNotEmpty) {
    return official;
  }
  return (item['companyName'] as String?)?.trim() ?? '';
}
