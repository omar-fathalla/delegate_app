import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Display-only info for a branch (Arabic display name + short address).
///
/// `branchName` remains the matching key everywhere (attendance logs,
/// photos, queries). This cache is used ONLY to decide what text to show.
class BranchDisplayInfo {
  final String displayNameAr;
  final String addressShort;
  const BranchDisplayInfo({this.displayNameAr = '', this.addressShort = ''});
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
    return _loading ??= FirebaseFirestore.instance
        .collection('branches')
        .get()
        .then(registerSnapshot)
        .catchError((_) {
      _loading = null;
    });
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
}
