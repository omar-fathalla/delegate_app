import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Cached display fields for a delegate used by branch attendance cards.
///
/// [fullName], [phoneNumber], and [personalPhotoURL] are treated as immutable
/// (no TTL). [companyName] expires after [companyNameTtl].
class CachedDelegateProfile {
  final String fullName;
  final String phoneNumber;
  final String? personalPhotoURL;
  final String companyName;
  final String? companyUID;
  final String? organizationUID;
  final int? companyNameCachedAtMs;

  const CachedDelegateProfile({
    required this.fullName,
    required this.phoneNumber,
    this.personalPhotoURL,
    required this.companyName,
    this.companyUID,
    this.organizationUID,
    this.companyNameCachedAtMs,
  });

  static const companyNameTtl = Duration(hours: 24);

  bool get hasUsableName => fullName.trim().isNotEmpty;
  bool get hasUsablePhone => phoneNumber.trim().isNotEmpty;
  bool get hasUsablePhoto =>
      personalPhotoURL != null && personalPhotoURL!.trim().isNotEmpty;

  String get effectiveCompanyName {
    if (companyName.trim().isEmpty) return '';
    final cachedAt = companyNameCachedAtMs;
    if (cachedAt == null) return companyName;
    final age = DateTime.now().millisecondsSinceEpoch - cachedAt;
    if (age > companyNameTtl.inMilliseconds) return '';
    return companyName;
  }

  Map<String, dynamic> toJson() => {
        'fullName': fullName,
        'phoneNumber': phoneNumber,
        'personalPhotoURL': personalPhotoURL,
        'companyName': companyName,
        'companyUID': companyUID,
        'organizationUID': organizationUID,
        'companyNameCachedAtMs': companyNameCachedAtMs,
      };

  factory CachedDelegateProfile.fromJson(Map<String, dynamic> json) {
    return CachedDelegateProfile(
      fullName: (json['fullName'] as String?) ?? '',
      phoneNumber: (json['phoneNumber'] as String?) ?? '',
      personalPhotoURL: json['personalPhotoURL'] as String?,
      companyName: (json['companyName'] as String?) ?? '',
      companyUID: json['companyUID'] as String?,
      organizationUID: json['organizationUID'] as String?,
      companyNameCachedAtMs: json['companyNameCachedAtMs'] as int?,
    );
  }

  CachedDelegateProfile merge(CachedDelegateProfile newer) {
    return CachedDelegateProfile(
      fullName: newer.hasUsableName ? newer.fullName : fullName,
      phoneNumber: newer.hasUsablePhone ? newer.phoneNumber : phoneNumber,
      personalPhotoURL:
          newer.hasUsablePhoto ? newer.personalPhotoURL : personalPhotoURL,
      companyName: newer.companyName.trim().isNotEmpty
          ? newer.companyName
          : companyName,
      companyUID: (newer.companyUID != null && newer.companyUID!.isNotEmpty)
          ? newer.companyUID
          : companyUID,
      organizationUID:
          (newer.organizationUID != null && newer.organizationUID!.isNotEmpty)
              ? newer.organizationUID
              : organizationUID,
      companyNameCachedAtMs: newer.companyName.trim().isNotEmpty
          ? newer.companyNameCachedAtMs
          : companyNameCachedAtMs,
    );
  }
}

/// Session + on-device persistent cache of delegate display profiles.
///
/// Shared by marketing home and BranchHomeScreen (same isolate / DI singleton).
class DelegateProfileCache {
  DelegateProfileCache({required SharedPreferences prefs}) : _prefs = prefs {
    _ensureLoaded();
  }

  final SharedPreferences _prefs;
  static const _prefsKey = 'delegate_profile_cache_v1';

  /// Process-wide session layer (also used by bench / tests via [clearSession]).
  static final Map<String, CachedDelegateProfile> session =
      <String, CachedDelegateProfile>{};

  final Map<String, CachedDelegateProfile> _persistent =
      <String, CachedDelegateProfile>{};
  bool _loaded = false;
  bool _dirty = false;

  void _ensureLoaded() {
    if (_loaded) return;
    _loaded = true;
    final raw = _prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = json.decode(raw);
      if (decoded is Map) {
        decoded.forEach((key, value) {
          if (key is String && value is Map) {
            _persistent[key] = CachedDelegateProfile.fromJson(
              Map<String, dynamic>.from(value),
            );
          }
        });
      }
    } catch (_) {}
  }

  /// Session first, then persistent disk.
  CachedDelegateProfile? get(String delegateId) {
    if (delegateId.isEmpty) return null;
    _ensureLoaded();
    final fromSession = session[delegateId];
    if (fromSession != null) return fromSession;
    return _persistent[delegateId];
  }

  Map<String, CachedDelegateProfile> getMany(Iterable<String> ids) {
    final out = <String, CachedDelegateProfile>{};
    for (final id in ids) {
      final p = get(id);
      if (p != null) out[id] = p;
    }
    return out;
  }

  void put(String delegateId, CachedDelegateProfile profile) {
    if (delegateId.isEmpty) return;
    _ensureLoaded();
    final existingSession = session[delegateId];
    final mergedSession =
        existingSession == null ? profile : existingSession.merge(profile);
    session[delegateId] = mergedSession;

    final existingPersisted = _persistent[delegateId];
    final mergedPersisted = existingPersisted == null
        ? profile
        : existingPersisted.merge(profile);
    _persistent[delegateId] = mergedPersisted;
    _dirty = true;
  }

  void putFromMaps({
    required String delegateId,
    String? fullName,
    String? phoneNumber,
    String? personalPhotoURL,
    String? companyName,
    String? companyUID,
    String? organizationUID,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    put(
      delegateId,
      CachedDelegateProfile(
        fullName: fullName?.trim() ?? '',
        phoneNumber: phoneNumber?.trim() ?? '',
        personalPhotoURL: personalPhotoURL?.trim(),
        companyName: companyName?.trim() ?? '',
        companyUID: companyUID,
        organizationUID: organizationUID,
        companyNameCachedAtMs:
            (companyName != null && companyName.trim().isNotEmpty) ? now : null,
      ),
    );
  }

  /// Flushes dirty entries to SharedPreferences (fire-and-forget OK).
  Future<void> persist() async {
    if (!_dirty) return;
    _ensureLoaded();
    final encoded = <String, dynamic>{
      for (final e in _persistent.entries) e.key: e.value.toJson(),
    };
    await _prefs.setString(_prefsKey, json.encode(encoded));
    _dirty = false;
  }

  static void clearSession() => session.clear();

  /// Test helper: wipe session + persistent maps (does not touch prefs until persist).
  void clearAllForTest() {
    session.clear();
    _persistent.clear();
    _dirty = true;
  }
}
