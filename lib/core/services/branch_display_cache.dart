import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Display-only info for a branch (Arabic display name + short address).
///
/// `branchName` remains the matching key everywhere (attendance logs,
/// photos, queries). This cache is used ONLY to decide what text to show.
class BranchDisplayInfo {
  final String displayNameAr;
  final String addressShort;
  final String organizationUID;
  final String organizationName;
  const BranchDisplayInfo({
    this.displayNameAr = '',
    this.addressShort = '',
    this.organizationUID = '',
    this.organizationName = '',
  });
}

class BranchDisplayCache {
  BranchDisplayCache._();
  static final BranchDisplayCache instance = BranchDisplayCache._();

  final Map<String, BranchDisplayInfo> _byName = {};

  /// Bumped whenever new display data is registered (for rebuilds).
  final ValueNotifier<int> version = ValueNotifier<int>(0);
  Future<void>? _loading;
  bool get isLoaded => _loaded;
  bool _loaded = false;

  static String _key(String name) => name.trim().toLowerCase();

  /// Registers display info from a raw `branches` document map.
  void registerFromMap(Map<String, dynamic> data, {String? docId}) {
    final info = BranchDisplayInfo(
      displayNameAr: (data['displayNameAr'] ?? '').toString().trim(),
      addressShort: (data['addressShort'] ?? '').toString().trim(),
      organizationUID: (data['organizationUID'] ?? '').toString().trim(),
      organizationName: (data['organizationName'] ?? '').toString().trim(),
    );
    final name = (data['branchName'] ?? '').toString();
    if (name.trim().isNotEmpty) _byName[_key(name)] = info;
    if (docId != null && docId.trim().isNotEmpty) _byName[_key(docId)] = info;
  }

  void registerSnapshot(QuerySnapshot<Map<String, dynamic>> snap) {
    for (final d in snap.docs) {
      registerFromMap(d.data(), docId: d.id);
    }
    _loaded = true;
    version.value++;
  }

  /// Loads all branches once (cheap: ~170 docs). Safe to call repeatedly.
  Future<void> ensureLoaded() {
    if (_loaded) return Future.value();
    final FirebaseFirestore db;
    try {
      db = FirebaseFirestore.instance;
    } catch (e, st) {
      // Firebase not initialised (e.g. widget tests): show raw names.
      debugPrint('BranchDisplayCache: Firestore unavailable: $e\n$st');
      return Future.value();
    }
    final future = db.collection('branches').get().then(registerSnapshot);
    late final Future<void> guarded;
    guarded = future.catchError((Object e, StackTrace st) {
      debugPrint('BranchDisplayCache: ensureLoaded failed: $e\n$st');
      if (identical(_loading, guarded)) _loading = null;
      Error.throwWithStackTrace(
        e is Exception ? e : Exception('$e'),
        st,
      );
    });
    _loading = guarded;
    return _loading!;
  }

  BranchDisplayInfo? infoFor(String? branchName) =>
      branchName == null ? null : _byName[_key(branchName)];

  /// displayNameAr if non-empty, else the original branchName.
  String displayName(String? branchName, {String fallback = ''}) {
    if (branchName == null || branchName.trim().isEmpty) return fallback;
    if (!_loaded) ensureLoaded();
    final ar = infoFor(branchName)?.displayNameAr ?? '';
    return ar.isNotEmpty ? ar : branchName;
  }

  String addressFor(String? branchName) =>
      infoFor(branchName)?.addressShort ?? '';

  // --- Chain / organization names (display only, read-only, cached) ---
  final Map<String, String> _orgNames = {};
  Future<void>? _orgLoading;

  /// Loads organization names once (organizations/{id}.name). Falls back to
  /// the branch's denormalized `organizationName` if this read fails.
  Future<void> ensureOrgsLoaded() {
    final FirebaseFirestore db;
    try {
      db = FirebaseFirestore.instance;
    } catch (e, st) {
      debugPrint('BranchDisplayCache: org load Firestore unavailable: $e\n$st');
      return Future.value();
    }
    final future = db.collection('organizations').get().then((snap) {
      for (final d in snap.docs) {
        final n = (d.data()['name'] ?? '').toString().trim();
        if (n.isNotEmpty) _orgNames[d.id] = n;
      }
      version.value++;
    });
    late final Future<void> guarded;
    guarded = future.catchError((Object e, StackTrace st) {
      debugPrint('BranchDisplayCache: ensureOrgsLoaded failed: $e\n$st');
      if (identical(_orgLoading, guarded)) _orgLoading = null;
      Error.throwWithStackTrace(
        e is Exception ? e : Exception('$e'),
        st,
      );
    });
    _orgLoading = guarded;
    return _orgLoading!;
  }

  /// Chain (organization) name for a branch, or '' if unknown.
  String organizationNameFor(String? branchName) {
    final info = infoFor(branchName);
    if (info == null) return '';
    if (_orgLoading == null) ensureOrgsLoaded();
    final fromOrg = _orgNames[info.organizationUID] ?? '';
    return fromOrg.isNotEmpty ? fromOrg : info.organizationName;
  }
}
