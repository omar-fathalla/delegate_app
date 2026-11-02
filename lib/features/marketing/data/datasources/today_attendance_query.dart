import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/config/read_reduction_flags.dart';
import 'package:delegate_app/core/constants.dart';
import 'package:delegate_app/core/services/firestore_resilience_helper.dart';
import 'package:delegate_app/core/utils/branch_key.dart';
import 'package:flutter/foundation.dart';

/// Hard cap per attendance query (guards runaway orgs / bad data).
const int kTodayAttendanceQueryLimit = 2000;

/// Firestore caps (filter clauses × whereIn size) at 100. With
/// organizationId + branchKey/branchName + timestamp>= + timestamp< (=4),
/// the max whereIn is 25; 20 leaves headroom.
const int kBranchWhereInChunkSize = 20;

/// Result of [fetchTodayAttendanceDocs].
class TodayAttendanceFetch {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;

  /// Number of Firestore queries issued (for metrics / tests).
  final int queries;

  /// Branches (original names) served by the legacy `branchName` fallback.
  final Set<String> legacyBranches;

  const TodayAttendanceFetch({
    required this.docs,
    required this.queries,
    required this.legacyBranches,
  });
}

List<List<T>> chunkList<T>(List<T> list, int size) => [
  for (var i = 0; i < list.length; i += size)
    list.sublist(i, i + size > list.length ? list.length : i + size),
];

/// Legacy `branchName` spelling variants (pre-`branchKey` docs). Kept exactly
/// as the pre-Phase-1 query built them so old records still match.
Set<String> legacyBranchNameVariants(String branch) {
  final trimmed = branch.trim();
  if (trimmed.isEmpty) return {};
  return {
    trimmed,
    trimmed.replaceAll(RegExp(r'[أإآ]'), 'ا'),
    trimmed.replaceAll('ا', 'أ'),
    trimmed.replaceAll('ه', 'ة'),
    trimmed.replaceAll('ة', 'ه'),
    trimmed.replaceAll('ى', 'ي'),
  };
}

/// Today's attendance docs for [branchNames] in [organizationId].
///
/// 1. When `use_branch_key_query` is on: one `branchKey` value per branch
///    (`organizationId == org`, `branchKey in`, timestamp in [dayStart, dayEnd)).
/// 2. Fallback (kept for old records without `branchKey`): branches that got
///    0 docs from step 1 are re-queried with the bounded legacy
///    `branchName in [variants]` query, unless `branch_key_backfilled` is on.
///    A `failed-precondition` (index not built yet) also falls back.
/// 3. When the flag is off, only the bounded legacy query runs.
Future<TodayAttendanceFetch> fetchTodayAttendanceDocs({
  required FirebaseFirestore firestore,
  required List<String> branchNames,
  required String organizationId,
  required DateTime dayStart,
  required DateTime dayEnd,
  ReadReductionFlags? flags,
  String collection = kAttendanceCollection,
}) async {
  final f = flags ?? ReadReductionFlags.instance;
  final startTs = Timestamp.fromDate(dayStart);
  final endTs = Timestamp.fromDate(dayEnd);
  final byId = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
  var queries = 0;

  final keyToBranches = <String, List<String>>{};
  for (final b in branchNames) {
    final k = branchKey(b);
    if (k.isEmpty) continue;
    keyToBranches.putIfAbsent(k, () => []).add(b);
  }

  Set<String> legacyTargets;
  if (f.useBranchKeyQuery) {
    final foundKeys = <String>{};
    var indexMissing = false;
    for (final chunk in chunkList(
      keyToBranches.keys.toList(),
      kBranchWhereInChunkSize,
    )) {
      try {
        queries++;
        final snap = await firestore
            .collection(collection)
            .where('organizationId', isEqualTo: organizationId)
            .where('branchKey', whereIn: chunk)
            .where('timestamp', isGreaterThanOrEqualTo: startTs)
            .where('timestamp', isLessThan: endTs)
            .limit(kTodayAttendanceQueryLimit)
            // Live attendance screen: freshness is the point of this query.
            .getResilient(forceServer: true);
        for (final d in snap.docs) {
          byId[d.id] = d;
          final k = d.data()['branchKey'];
          if (k is String) foundKeys.add(k);
        }
      } on FirebaseException catch (e) {
        if (e.code != 'failed-precondition') rethrow;
        debugPrint(
          'branchKey query needs index, using legacy query: ${e.message}',
        );
        indexMissing = true;
      }
    }
    legacyTargets = indexMissing
        ? branchNames.toSet()
        : f.branchKeyBackfilled
        ? <String>{}
        : {
            for (final e in keyToBranches.entries)
              if (!foundKeys.contains(e.key)) ...e.value,
          };
  } else {
    legacyTargets = branchNames.toSet();
  }

  if (legacyTargets.isNotEmpty) {
    final terms = <String>{
      for (final b in legacyTargets) ...legacyBranchNameVariants(b),
    };
    for (final chunk in chunkList(terms.toList(), kBranchWhereInChunkSize)) {
      queries++;
      final snap = await firestore
          .collection(collection)
          .where('organizationId', isEqualTo: organizationId)
          .where('branchName', whereIn: chunk)
          .where('timestamp', isGreaterThanOrEqualTo: startTs)
          .where('timestamp', isLessThan: endTs)
          .limit(kTodayAttendanceQueryLimit)
          // Bounded fallback: default source (no forceServer) per plan §1.5.
          .get();
      for (final d in snap.docs) {
        byId[d.id] = d;
      }
    }
  }

  return TodayAttendanceFetch(
    docs: byId.values.toList(),
    queries: queries,
    legacyBranches: legacyTargets,
  );
}

/// Today-only snapshot listener used as the branch screen's refresh signal.
///
/// Emits the number of added/modified/removed docs whenever any of today's
/// `branchKey` docs for [branchNames] change. The initial snapshot of each
/// chunk is swallowed (the screen already loaded it), so after the first
/// bill only changed docs are read. Cancel the subscription to pause.
Stream<int> watchTodayBranchAttendanceChanges({
  required FirebaseFirestore firestore,
  required List<String> branchNames,
  required String organizationId,
  required DateTime dayStart,
  required DateTime dayEnd,
  String collection = kAttendanceCollection,
}) {
  final keys = branchNames
      .map(branchKey)
      .where((k) => k.isNotEmpty)
      .toSet()
      .toList();
  if (keys.isEmpty) return const Stream.empty();
  final startTs = Timestamp.fromDate(dayStart);
  final endTs = Timestamp.fromDate(dayEnd);
  late final StreamController<int> controller;
  final subs = <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];
  controller = StreamController<int>(
    onListen: () {
      for (final chunk in chunkList(keys, kBranchWhereInChunkSize)) {
        var first = true;
        subs.add(
          firestore
              .collection(collection)
              .where('organizationId', isEqualTo: organizationId)
              .where('branchKey', whereIn: chunk)
              .where('timestamp', isGreaterThanOrEqualTo: startTs)
              .where('timestamp', isLessThan: endTs)
              .limit(kTodayAttendanceQueryLimit)
              .snapshots()
              .listen(
                (snap) {
                  if (first) {
                    first = false;
                    return;
                  }
                  // Skip our own pending local writes; the server echo follows.
                  if (snap.metadata.hasPendingWrites) return;
                  if (snap.docChanges.isNotEmpty) {
                    controller.add(snap.docChanges.length);
                  }
                },
                onError: (Object e) {
                  debugPrint('branch attendance listener error: $e');
                },
              ),
        );
      }
    },
    onCancel: () async {
      for (final s in subs) {
        await s.cancel();
      }
      subs.clear();
    },
  );
  return controller.stream;
}
