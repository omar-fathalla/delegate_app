import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// حفظ واسترجاع الفروع المفضلة وIndex الفرع النشط لكل مستخدم تسويق
class BranchPreferenceService {
  final SharedPreferences _prefs;

  BranchPreferenceService({required SharedPreferences prefs}) : _prefs = prefs;

  // ─── Keys ────────────────────────────────────────────
  String _favKey(String userId) => 'marketing_fav_branches_$userId';
  String _activeKey(String userId) => 'marketing_active_branch_$userId';

  // ─── Favorites ───────────────────────────────────────

  /// Returns the list of favorite branch names for [userId].
  List<String> getFavoriteBranches(String userId) {
    try {
      final raw = _prefs.getString(_favKey(userId));
      if (raw == null) return [];
      final list = json.decode(raw) as List<dynamic>;
      return list.map((e) => e.toString()).toList();
    } catch (_) {
      return [];
    }
  }

  /// Adds [branchName] to favorites if not already present.
  Future<void> addFavoriteBranch(String userId, String branchName) async {
    final current = getFavoriteBranches(userId);
    if (!current.contains(branchName)) {
      current.add(branchName);
      await _prefs.setString(_favKey(userId), json.encode(current));
      // إذا كانت أول فرع -> يصبح النشط تلقائياً
      if (current.length == 1) {
        await setActiveBranch(userId, branchName);
      }
    }
  }

  /// Removes [branchName] from favorites.
  Future<void> removeFavoriteBranch(String userId, String branchName) async {
    final current = getFavoriteBranches(userId);
    current.remove(branchName);
    await _prefs.setString(_favKey(userId), json.encode(current));

    // إذا كان الفرع المحذوف هو النشط، اجعل الأول نشطاً أو فارغاً
    final active = getActiveBranch(userId);
    if (active == branchName) {
      await setActiveBranch(userId, current.isNotEmpty ? current.first : null);
    }
  }

  // ─── Active Branch ────────────────────────────────────

  /// Returns the currently active (displayed) branch name or null.
  String? getActiveBranch(String userId) {
    return _prefs.getString(_activeKey(userId));
  }

  /// Sets [branchName] as the active branch. Pass null to clear.
  Future<void> setActiveBranch(String userId, String? branchName) async {
    if (branchName == null) {
      await _prefs.remove(_activeKey(userId));
    } else {
      await _prefs.setString(_activeKey(userId), branchName);
    }
  }

  /// True if the user has at least one favorite branch saved.
  bool hasFavoriteBranches(String userId) {
    return getFavoriteBranches(userId).isNotEmpty;
  }

  /// Clear all preferences for [userId] (e.g., on logout).
  Future<void> clearAll(String userId) async {
    await _prefs.remove(_favKey(userId));
    await _prefs.remove(_activeKey(userId));
  }
}
