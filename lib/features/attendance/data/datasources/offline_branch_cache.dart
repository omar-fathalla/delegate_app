import 'dart:convert';

import 'package:delegate_app/core/attendance/attendance_branch_ref.dart';
import 'package:delegate_app/features/admin/domain/entities/branch.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where a branch is, kept on the phone for an offline check-in (TAS-363).
class CachedBranchLocation {
  const CachedBranchLocation({
    required this.branchName,
    required this.latitude,
    required this.longitude,
    required this.geofenceRadius,
    this.branchId,
  });

  /// Branch doc id (the callable needs it); null for a name-only branch.
  final String? branchId;
  final String branchName;
  final double latitude;
  final double longitude;
  final double geofenceRadius;

  bool get hasCoordinates => !(latitude == 0.0 && longitude == 0.0);

  Map<String, dynamic> toJson() => {
    'n': branchName,
    'lat': latitude,
    'lng': longitude,
    'r': geofenceRadius,
    'id': ?branchId,
  };

  static CachedBranchLocation? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final lat = raw['lat'], lng = raw['lng'], r = raw['r'];
    if (lat is! num || lng is! num) return null;
    return CachedBranchLocation(
      branchName: (raw['n'] as String?) ?? '',
      latitude: lat.toDouble(),
      longitude: lng.toDouble(),
      geofenceRadius: r is num ? r.toDouble() : 0.0,
      branchId: raw['id'] as String?,
    );
  }
}

/// Branch coordinates saved every time the delegate's branches are read with
/// network (attendance screen, online check-in), so the geofence can run
/// without network. The server re-checks the distance when the record is
/// sent. Branch data only (no personal data), kept on logout.
class OfflineBranchCache {
  OfflineBranchCache(this._prefs);

  static const String key = 'offline_branch_locations_v1';
  static const int maxEntries = 600;

  final SharedPreferences _prefs;

  static String _idKey(String org, String branchId) =>
      '${org.trim()}|id:${branchId.trim()}';
  static String _nameKey(String org, String name) =>
      '${org.trim()}|name:${name.trim()}';

  Map<String, dynamic> _read() {
    try {
      final raw = _prefs.getString(key);
      if (raw == null) return <String, dynamic>{};
      final decoded = json.decode(raw);
      return decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  /// Saves [branches] of [organizationUID] (only those with coordinates).
  Future<void> saveAll(
    String organizationUID,
    Iterable<Branch> branches,
  ) async {
    final map = _read();
    for (final b in branches) {
      final org = (b.organizationUID ?? organizationUID).trim();
      if (org.isEmpty) continue;
      _put(
        map,
        org,
        b.id,
        CachedBranchLocation(
          branchId: b.id.trim().isEmpty ? null : b.id.trim(),
          branchName: b.branchName,
          latitude: b.latitude,
          longitude: b.longitude,
          geofenceRadius: b.geofenceRadius,
        ),
      );
    }
    await _write(map);
  }

  Future<void> save(
    String organizationUID,
    String? branchId,
    CachedBranchLocation location,
  ) async {
    final map = _read();
    _put(map, organizationUID.trim(), branchId, location);
    await _write(map);
  }

  void _put(
    Map<String, dynamic> map,
    String org,
    String? branchId,
    CachedBranchLocation loc,
  ) {
    if (org.isEmpty || !loc.hasCoordinates) return;
    final id = branchId?.trim() ?? loc.branchId;
    final value = CachedBranchLocation(
      branchId: (id == null || id.isEmpty) ? null : id,
      branchName: loc.branchName,
      latitude: loc.latitude,
      longitude: loc.longitude,
      geofenceRadius: loc.geofenceRadius,
    ).toJson();
    if (branchId != null && branchId.trim().isNotEmpty) {
      map.remove(_idKey(org, branchId));
      map[_idKey(org, branchId)] = value;
    }
    if (loc.branchName.trim().isNotEmpty) {
      map.remove(_nameKey(org, loc.branchName));
      map[_nameKey(org, loc.branchName)] = value;
    }
  }

  Future<void> _write(Map<String, dynamic> map) async {
    // Keep the newest entries (insertion order) under the cap.
    while (map.length > maxEntries) {
      map.remove(map.keys.first);
    }
    try {
      await _prefs.setString(key, json.encode(map));
    } catch (_) {}
  }

  /// The saved location of [ref] (by id, then by name in its chain).
  CachedBranchLocation? find(AttendanceBranchRef ref) {
    final map = _read();
    final org = ref.branchOrganizationUID.trim();
    final id = ref.branchId?.trim() ?? '';
    if (id.isNotEmpty) {
      final hit = CachedBranchLocation.fromJson(map[_idKey(org, id)]);
      if (hit != null) return hit;
    }
    if (ref.branchName.trim().isNotEmpty) {
      return CachedBranchLocation.fromJson(map[_nameKey(org, ref.branchName)]);
    }
    return null;
  }

  /// Every saved branch of [organizationUID], for the screen's offline
  /// "nearest branch" check.
  List<Branch> branchesOf(String organizationUID) {
    final org = organizationUID.trim();
    final out = <Branch>[];
    _read().forEach((k, v) {
      if (!k.startsWith('$org|id:')) return;
      final loc = CachedBranchLocation.fromJson(v);
      if (loc == null) return;
      out.add(
        Branch(
          id: k.substring('$org|id:'.length),
          branchName: loc.branchName,
          latitude: loc.latitude,
          longitude: loc.longitude,
          geofenceRadius: loc.geofenceRadius,
          organizationUID: org,
        ),
      );
    });
    return out;
  }
}
