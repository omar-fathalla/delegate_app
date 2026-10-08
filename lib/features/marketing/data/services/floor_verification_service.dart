import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:delegate_app/features/marketing/data/models/floor_verification_model.dart';

/// Service responsible for local cache (0ms) and Firestore sync of floor verification checks
class FloorVerificationService extends ChangeNotifier {
  final SharedPreferences _prefs;
  final FirebaseFirestore _firestore;

  static const String _collectionName = 'floor_checks';

  FloorVerificationService({
    required SharedPreferences prefs,
    required FirebaseFirestore firestore,
  })  : _prefs = prefs,
        _firestore = firestore;

  String _localKey(String dateStr) => 'floor_verifications_$dateStr';

  String _formatDate(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

  // ─── Local Cache (0ms Instant Synchronous Read) ───────────────────────────

  /// Gets all floor verification checks for [date] from local persistent cache
  Map<String, FloorVerificationItem> getLocalVerifications(DateTime date) {
    try {
      final key = _localKey(_formatDate(date));
      final raw = _prefs.getString(key);
      if (raw == null || raw.isEmpty) return {};
      final decoded = json.decode(raw) as Map<String, dynamic>;
      final result = <String, FloorVerificationItem>{};
      for (final entry in decoded.entries) {
        if (entry.value is Map<String, dynamic>) {
          result[entry.key] = FloorVerificationItem.fromJson(
            Map<String, dynamic>.from(entry.value as Map),
          );
        }
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  /// Saves or updates a floor check item in local cache and triggers background cloud sync
  Future<void> saveVerification({
    required FloorVerificationItem item,
    bool syncToCloud = true,
  }) async {
    try {
      final key = _localKey(item.date);
      final current = getLocalVerifications(DateTime.parse(item.date));
      current[item.delegateId] = item;

      final encoded = <String, dynamic>{
        for (final entry in current.entries) entry.key: entry.value.toJson(),
      };
      await _prefs.setString(key, json.encode(encoded));
      notifyListeners();

      if (syncToCloud) {
        _syncToCloudInBackground(item);
      }
    } catch (_) {}
  }

  /// Removes a floor check item from local cache and deletes from cloud in background
  Future<void> removeVerification({
    required String dateStr,
    required String branchName,
    required String delegateId,
    bool syncToCloud = true,
  }) async {
    try {
      final key = _localKey(dateStr);
      final current = getLocalVerifications(DateTime.parse(dateStr));
      current.remove(delegateId);

      final encoded = <String, dynamic>{
        for (final entry in current.entries) entry.key: entry.value.toJson(),
      };
      await _prefs.setString(key, json.encode(encoded));
      notifyListeners();

      if (syncToCloud) {
        _deleteFromCloudInBackground(dateStr, branchName, delegateId);
      }
    } catch (_) {}
  }

  /// Clears all verifications for a specific branch on [date]
  Future<void> clearBranchVerifications({
    required DateTime date,
    required String branchName,
  }) async {
    try {
      final dateStr = _formatDate(date);
      final key = _localKey(dateStr);
      final current = getLocalVerifications(date);

      final toRemove = <String>[];
      for (final entry in current.entries) {
        if (entry.value.branchName == branchName) {
          toRemove.add(entry.key);
        }
      }

      for (final id in toRemove) {
        current.remove(id);
        _deleteFromCloudInBackground(dateStr, branchName, id);
      }

      final encoded = <String, dynamic>{
        for (final entry in current.entries) entry.key: entry.value.toJson(),
      };
      await _prefs.setString(key, json.encode(encoded));
      notifyListeners();
    } catch (_) {}
  }

  // ─── Cloud Sync (Stale-While-Revalidate) ───────────────────────────────────

  /// Fetches verification records from Firestore for [branchNames] on [date] and merges into cache
  Future<Map<String, FloorVerificationItem>> fetchCloudVerifications({
    required DateTime date,
    required List<String> branchNames,
  }) async {
    if (branchNames.isEmpty) return getLocalVerifications(date);

    final dateStr = _formatDate(date);
    final localMap = getLocalVerifications(date);

    try {
      // Chunk branches by 30 for whereIn query
      final chunks = <List<String>>[];
      for (var i = 0; i < branchNames.length; i += 30) {
        chunks.add(branchNames.sublist(
          i,
          (i + 30 > branchNames.length) ? branchNames.length : i + 30,
        ));
      }

      for (final chunk in chunks) {
        final snap = await _firestore
            .collection(_collectionName)
            .where('date', isEqualTo: dateStr)
            .where('branchName', whereIn: chunk)
            .get();

        for (final doc in snap.docs) {
          final data = doc.data();
          final item = FloorVerificationItem.fromJson(data);
          if (item.delegateId.isNotEmpty) {
            localMap[item.delegateId] = item;
          }
        }
      }

      // Persist merged map to local cache
      final key = _localKey(dateStr);
      final encoded = <String, dynamic>{
        for (final entry in localMap.entries) entry.key: entry.value.toJson(),
      };
      await _prefs.setString(key, json.encode(encoded));
      notifyListeners();

      return localMap;
    } catch (_) {
      // Return local cache on any network failure
      return localMap;
    }
  }

  void _syncToCloudInBackground(FloorVerificationItem item) {
    // Non-blocking fire-and-forget sync
    final docId = '${item.date}_${item.branchName}_${item.delegateId}';
    _firestore
        .collection(_collectionName)
        .doc(docId)
        .set({
          ...item.toJson(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true))
        .catchError((_) {});
  }

  void _deleteFromCloudInBackground(String dateStr, String branchName, String delegateId) {
    final docId = '${dateStr}_${branchName}_$delegateId';
    _firestore.collection(_collectionName).doc(docId).delete().catchError((_) {});
  }
}
