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

/// Upper bound on generated spellings per branch (keeps the fallback to a
/// few `whereIn` chunks even for long multi-word names).
const int kMaxLegacyVariantsPerBranch = 64;

/// Legacy `branchName` spelling variants (pre-`branchKey` docs).
///
/// Generated from the [branchKey] normalizer instead of a fixed list, so every
/// combination is covered (e.g. «الابراهيميه», which mixes a plain alef with a
/// final ه, was missing from the old 6-variant list):
/// * a word-initial alef (or the alef right after a leading «ال») can be
///   ا / أ / إ / آ;
/// * a word-final ه can be ه / ة; a word-final ي can be ي / ى.
/// The original trimmed spelling is always included. Capped at
/// [kMaxLegacyVariantsPerBranch].
Set<String> legacyBranchNameVariants(String branch) {
  final trimmed = branch.trim();
  if (trimmed.isEmpty) return {};
  final out = <String>{trimmed, trimmed.replaceAll(RegExp(r'\s+'), ' ')};
  final key = branchKey(trimmed);
  final words = key.split(' ');
  // Per-word list of options; product = variants.
  final perWord = <List<String>>[];
  for (final w in words) {
    var options = <String>[w];
    List<String> expand(List<String> src, int index, List<String> chars) => [
      for (final o in src)
        for (final c in chars)
          o.substring(0, index) + c + o.substring(index + 1),
    ];
    final alefIndex = w.startsWith('ال') && w.length > 2 ? 2 : 0;
    if (w.length > alefIndex && w[alefIndex] == 'ا') {
      options = expand(options, alefIndex, const ['ا', 'أ', 'إ', 'آ']);
    }
    final last = w.length - 1;
    if (last > 0 && w[last] == 'ه') {
      options = expand(options, last, const ['ه', 'ة']);
    } else if (last > 0 && w[last] == 'ي') {
      options = expand(options, last, const ['ي', 'ى']);
    }
    perWord.add(options);
  }
  var combos = <String>[''];
  for (var i = 0; i < perWord.length; i++) {
    combos = [
      for (final c in combos)
        for (final o in perWord[i]) i == 0 ? o : '$c $o',
    ];
    if (combos.length > kMaxLegacyVariantsPerBranch) {
      combos = combos.sublist(0, kMaxLegacyVariantsPerBranch);
    }
  }
  out.addAll(combos);
  return out;
}

/// Today's attendance docs for [branchNames] in [organizationId].
///
/// * Before the backfill (`branch_key_backfilled` off) or with
///   `use_branch_key_query` off: only the bounded legacy
///   `branchName in [variants]` query runs (it covers old AND new docs).
/// * Once backfilled: one `branchKey` value per branch
///   (`organizationId == org`, `branchKey in`, timestamp in [dayStart, dayEnd)).
///   A `failed-precondition` (index not built yet) falls back to legacy.
/// Results are deduped by doc id; `whereIn` lists are chunked by 20.
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

  // Until the backfill is confirmed, old app versions may still write docs
  // without `branchKey`, and the legacy `branchName` query already covers
  // every doc (new docs carry branchName too). So pre-backfill ONLY the
  // legacy query runs; the keyed query is used only once backfilled.
  Set<String> legacyTargets;
  if (f.useBranchKeyQuery && f.branchKeyBackfilled) {
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
        }
      } on FirebaseException catch (e) {
        if (e.code != 'failed-precondition') rethrow;
        debugPrint(
          'branchKey query needs index, using legacy query: ${e.message}',
        );
        indexMissing = true;
        break;
      }
    }
    legacyTargets = indexMissing ? branchNames.toSet() : <String>{};
    if (indexMissing) byId.clear();
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
                onError: (Object e, StackTrace st) {
                  debugPrint('branch attendance listener error: $e');
                  // Surface it so the screen can fall back to polling.
                  if (!controller.isClosed) controller.addError(e, st);
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
