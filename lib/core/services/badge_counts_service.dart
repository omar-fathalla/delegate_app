import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Loads a count for a badge key. Returns null on failure.
typedef BadgeCountLoader = Future<int?> Function(BadgeCountKey key);

/// Identifies one "pending items" badge: `collection` filtered by
/// `status == 'pending'` and, when non-empty, `companyUID`.
@immutable
class BadgeCountKey {
  const BadgeCountKey(this.collection, this.companyUID);

  final String collection;
  final String companyUID;

  @override
  bool operator ==(Object other) =>
      other is BadgeCountKey &&
      other.collection == collection &&
      other.companyUID == companyUID;

  @override
  int get hashCode => Object.hash(collection, companyUID);

  @override
  String toString() => '$collection|$companyUID';
}

/// Read-reduction Phase 3: shared pending-count badges.
///
/// Before, every badge was a `.snapshots()` listener that downloaded every
/// pending document just to show `docs.length`, and the same query was opened
/// separately by the sidebar, bottom sheet and main screens. This service
/// uses `count()` aggregation (1 read per 1000 matched docs), shares one poll
/// per key across all widgets, refreshes at most once per [minInterval] while
/// someone is listening, and stops polling when nobody is.
class BadgeCountsService {
  BadgeCountsService({
    BadgeCountLoader? loader,
    this.minInterval = const Duration(seconds: 60),
    DateTime Function()? clock,
  }) : _loader = loader ?? _firestoreCount,
       _clock = clock ?? DateTime.now;

  static final BadgeCountsService instance = BadgeCountsService();

  final BadgeCountLoader _loader;
  final Duration minInterval;
  final DateTime Function() _clock;

  final Map<BadgeCountKey, _BadgeEntry> _entries = {};

  static Future<int?> _firestoreCount(BadgeCountKey key) async {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance.collection(
      key.collection,
    );
    if (key.companyUID.isNotEmpty) {
      q = q.where('companyUID', isEqualTo: key.companyUID);
    }
    q = q.where('status', isEqualTo: 'pending');
    final snap = await q.count().get();
    return snap.count;
  }

  /// Latest known value (0 until the first load). Listening to this does not
  /// start polling; use [watch] for that.
  ValueListenable<int> notifier(BadgeCountKey key) => _entry(key).value;

  /// Stream of counts for [key]. Emits the cached value immediately, polls
  /// every [minInterval] while subscribed.
  Stream<int> watch(String collection, String companyUID) {
    final entry = _entry(BadgeCountKey(collection, companyUID));
    late StreamController<int> controller;
    void onChange() {
      if (!controller.isClosed) controller.add(entry.value.value);
    }

    controller = StreamController<int>(
      onListen: () {
        entry.listeners++;
        entry.value.addListener(onChange);
        if (entry.loadedAt != null) controller.add(entry.value.value);
        _ensurePolling(entry);
      },
      onCancel: () {
        entry.value.removeListener(onChange);
        entry.listeners--;
        if (entry.listeners <= 0) {
          entry.listeners = 0;
          entry.timer?.cancel();
          entry.timer = null;
        }
      },
    );
    return controller.stream;
  }

  /// Forces a refresh (e.g. after approving a request), ignoring the throttle.
  Future<void> invalidate(String collection, String companyUID) =>
      _refresh(_entry(BadgeCountKey(collection, companyUID)), force: true);

  _BadgeEntry _entry(BadgeCountKey key) =>
      _entries.putIfAbsent(key, () => _BadgeEntry(key));

  void _ensurePolling(_BadgeEntry entry) {
    unawaited(_refresh(entry));
    entry.timer ??= Timer.periodic(minInterval, (_) => _refresh(entry));
  }

  Future<void> _refresh(_BadgeEntry entry, {bool force = false}) {
    final last = entry.loadedAt;
    if (!force && last != null && _clock().difference(last) < minInterval) {
      return Future.value();
    }
    return entry.inFlight ??= () async {
      try {
        final count = await _loader(entry.key);
        if (count != null) {
          entry.loadedAt = _clock();
          entry.value.value = count;
        }
      } catch (e) {
        debugPrint('BadgeCountsService ${entry.key}: $e');
      } finally {
        entry.inFlight = null;
      }
    }();
  }

  @visibleForTesting
  void debugReset() {
    for (final e in _entries.values) {
      e.timer?.cancel();
    }
    _entries.clear();
  }
}

class _BadgeEntry {
  _BadgeEntry(this.key);

  final BadgeCountKey key;
  final ValueNotifier<int> value = ValueNotifier<int>(0);
  DateTime? loadedAt;
  Timer? timer;
  int listeners = 0;
  Future<void>? inFlight;
}
