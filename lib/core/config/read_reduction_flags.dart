import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

/// Kill switches for the Firestore read-reduction work.
///
/// Values come from Firebase Remote Config (already used by
/// `DelegateOtpConfig`), read at the moment of use from the values that
/// `DelegateOtpConfig.refreshFromRemoteConfig` activated. This class never
/// calls `setDefaults`, so it cannot change the OTP key's default; a key that
/// was never published (`ValueSource.valueStatic`) falls back to the in-app
/// default below. Tests can pin values with [ReadReductionFlags.fixed].
///
/// Remote Config keys (none are published by this code):
/// - `use_branch_key_query` (default true): query `attendance_logs` by the
///   normalized `branchKey` instead of ~6 `branchName` spelling variants.
/// - `branch_key_backfilled` (default false): when false, a branch whose
///   `branchKey` query returns 0 docs is re-queried with the bounded legacy
///   `branchName in [...]` query (old docs / old app versions).
/// - `branch_live_listener` (default true): branch screen uses a today-only
///   snapshot listener as its refresh signal instead of a 30 s timer.
/// - `lazy_tabs` (default true): bottom-nav tabs build on first visit.
class ReadReductionFlags {
  static const String useBranchKeyQueryKey = 'use_branch_key_query';
  static const String branchKeyBackfilledKey = 'branch_key_backfilled';
  static const String branchLiveListenerKey = 'branch_live_listener';
  static const String lazyTabsKey = 'lazy_tabs';

  static const Map<String, bool> defaults = {
    useBranchKeyQueryKey: true,
    branchKeyBackfilledKey: false,
    branchLiveListenerKey: true,
    lazyTabsKey: true,
  };

  /// Shared instance used by production code.
  static ReadReductionFlags instance = ReadReductionFlags._remote();

  final Map<String, bool>? _fixed;

  ReadReductionFlags._remote() : _fixed = null;

  /// Pinned values for tests; missing keys use [defaults].
  @visibleForTesting
  ReadReductionFlags.fixed([Map<String, bool> values = const {}])
    : _fixed = {...defaults, ...values};

  bool get useBranchKeyQuery => _read(useBranchKeyQueryKey);
  bool get branchKeyBackfilled => _read(branchKeyBackfilledKey);
  bool get branchLiveListener => _read(branchLiveListenerKey);
  bool get lazyTabs => _read(lazyTabsKey);

  bool _read(String key) {
    final fixed = _fixed;
    if (fixed != null) return fixed[key] ?? defaults[key]!;
    try {
      final value = FirebaseRemoteConfig.instance.getValue(key);
      if (value.source == ValueSource.valueStatic) return defaults[key]!;
      return value.asBool();
    } catch (_) {
      // Firebase not initialized (tests, early startup) → in-app default.
      return defaults[key]!;
    }
  }
}
