import 'dart:convert';
import 'dart:io';

import 'package:delegate_app/features/private_label/data/models/private_label_audit_model.dart';
import 'package:delegate_app/features/private_label/data/models/private_label_day_model.dart';
import 'package:delegate_app/features/private_label/data/models/private_label_product_model.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_audit_draft.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cached month payload.
class CachedPrivateLabelMonth {
  final List<PrivateLabelDayModel> days;
  final int restAllowance;

  const CachedPrivateLabelMonth({required this.days, required this.restAllowance});
}

abstract class PrivateLabelLocalDataSource {
  CachedPrivateLabelMonth? getCachedMonth(String organizationUID, String delegateUid, String monthKey);

  Future<void> cacheMonth(
    String organizationUID,
    String delegateUid,
    String monthKey,
    List<PrivateLabelDayModel> days,
    int restAllowance,
  );

  List<PrivateLabelProductModel> getCachedProducts(String organizationUID);

  Future<void> cacheProducts(String organizationUID, List<PrivateLabelProductModel> products);

  List<String> getCachedBranches(String organizationUID);

  Future<void> cacheBranches(String organizationUID, List<String> branches);

  List<PrivateLabelAuditDraft> getPendingDrafts(String delegateUid);

  Future<void> addPendingDraft(PrivateLabelAuditDraft draft);

  Future<void> removePendingDraft(String draftId);

  /// Copies a captured image into a persistent directory (no-op on web).
  Future<String> persistImage(String sourcePath, String fileName);

  Future<void> deleteImage(String path);
}

class PrivateLabelLocalDataSourceImpl implements PrivateLabelLocalDataSource {
  static const String pendingKey = 'pl_pending_audits_v1';
  static const String persistentDirName = 'private_label_pending';

  final SharedPreferences sharedPreferences;

  PrivateLabelLocalDataSourceImpl({required this.sharedPreferences});

  // Per-organization + per-user keys (no cache contamination between sessions).
  String _monthKey(String org, String uid, String month) => 'pl_month_${org}_${uid}_$month';
  String _productsKey(String org) => 'pl_products_$org';
  String _branchesKey(String org) => 'pl_branches_$org';

  @override
  CachedPrivateLabelMonth? getCachedMonth(String organizationUID, String delegateUid, String monthKey) {
    try {
      final raw = sharedPreferences.getString(_monthKey(organizationUID, delegateUid, monthKey));
      if (raw == null) return null;
      final map = json.decode(raw) as Map<String, dynamic>;
      final days = (map['days'] as List<dynamic>? ?? [])
          .map((e) => PrivateLabelDayModel.fromLocalJson(Map<String, dynamic>.from(e as Map)))
          .where((d) => d.delegateUid == delegateUid)
          .toList();
      final allowance = (map['restAllowance'] as num?)?.toInt() ?? 4;
      return CachedPrivateLabelMonth(days: days, restAllowance: allowance);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> cacheMonth(
    String organizationUID,
    String delegateUid,
    String monthKey,
    List<PrivateLabelDayModel> days,
    int restAllowance,
  ) async {
    await sharedPreferences.setString(
      _monthKey(organizationUID, delegateUid, monthKey),
      json.encode({
        'restAllowance': restAllowance,
        'days': days.map((d) => d.toLocalJson()).toList(),
      }),
    );
  }

  @override
  List<PrivateLabelProductModel> getCachedProducts(String organizationUID) {
    try {
      final raw = sharedPreferences.getString(_productsKey(organizationUID));
      if (raw == null) return const [];
      return (json.decode(raw) as List<dynamic>)
          .map((e) => PrivateLabelProductModel.fromLocalJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> cacheProducts(String organizationUID, List<PrivateLabelProductModel> products) async {
    await sharedPreferences.setString(
      _productsKey(organizationUID),
      json.encode(products.map((p) => p.toLocalJson()).toList()),
    );
  }

  @override
  List<String> getCachedBranches(String organizationUID) =>
      sharedPreferences.getStringList(_branchesKey(organizationUID)) ?? const [];

  @override
  Future<void> cacheBranches(String organizationUID, List<String> branches) async {
    await sharedPreferences.setStringList(_branchesKey(organizationUID), branches);
  }

  List<PrivateLabelAuditDraft> _allPending() {
    final raw = sharedPreferences.getStringList(pendingKey) ?? const [];
    final result = <PrivateLabelAuditDraft>[];
    for (final item in raw) {
      try {
        result.add(PrivateLabelAuditDraftJson.fromJson(json.decode(item) as Map<String, dynamic>));
      } catch (_) {
        // Skip corrupted entries instead of breaking the whole queue.
      }
    }
    return result;
  }

  Future<void> _saveAllPending(List<PrivateLabelAuditDraft> drafts) async {
    await sharedPreferences.setStringList(
      pendingKey,
      drafts.map((d) => json.encode(PrivateLabelAuditDraftJson.toJson(d))).toList(),
    );
  }

  @override
  List<PrivateLabelAuditDraft> getPendingDrafts(String delegateUid) {
    final list = _allPending().where((d) => d.delegateUid == delegateUid).toList();
    list.sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
    return list;
  }

  @override
  Future<void> addPendingDraft(PrivateLabelAuditDraft draft) async {
    final all = _allPending()..removeWhere((d) => d.id == draft.id);
    all.add(draft);
    await _saveAllPending(all);
  }

  @override
  Future<void> removePendingDraft(String draftId) async {
    final all = _allPending()..removeWhere((d) => d.id == draftId);
    await _saveAllPending(all);
  }

  @override
  Future<String> persistImage(String sourcePath, String fileName) async {
    if (kIsWeb) return sourcePath;
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final dir = Directory('${appDir.path}/$persistentDirName');
      if (!await dir.exists()) await dir.create(recursive: true);
      final target = '${dir.path}/$fileName';
      if (sourcePath == target) return sourcePath;
      final saved = await File(sourcePath).copy(target);
      return saved.path;
    } catch (_) {
      return sourcePath;
    }
  }

  @override
  Future<void> deleteImage(String path) async {
    if (kIsWeb || path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists() && path.contains(persistentDirName)) {
        await file.delete();
      }
    } catch (_) {}
  }
}
