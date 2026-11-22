import 'dart:async';

import 'package:delegate_app/core/services/firestore_cache_reset.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// TAS-76: logout marks, the next session start clears, pending writes win.
void main() {
  late SharedPreferences prefs;
  late List<String> calls;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    calls = [];
    FirestoreCacheReset.debugReset();
  });

  FirestoreCacheReset reset({
    Future<void> Function()? wait,
    bool isWeb = false,
    Duration timeout = const Duration(milliseconds: 50),
  }) =>
      FirestoreCacheReset(
        prefs: prefs,
        isWeb: isWeb,
        pendingWritesTimeout: timeout,
        waitForPendingWrites: wait ?? () async => calls.add('wait'),
        terminate: () async => calls.add('terminate'),
        clearPersistence: () async => calls.add('clear'),
      );

  test('nothing happens without a logout mark', () async {
    expect(await reset().runIfPending(), isFalse);
    expect(calls, isEmpty);
  });

  test('a marked reset terminates, clears and drops the mark', () async {
    await reset().markPending();
    expect(reset().isPending, isTrue);
    expect(await reset().runIfPending(), isTrue);
    expect(calls, ['wait', 'terminate', 'clear']);
    expect(reset().isPending, isFalse);
  });

  test('unsent writes postpone the reset and keep the mark', () async {
    await reset().markPending();
    final never = Completer<void>();
    final done = await reset(wait: () => never.future).runIfPending();
    expect(done, isFalse);
    expect(calls, isEmpty, reason: 'no terminate/clear while writes are pending');
    expect(reset().isPending, isTrue);
  });

  test('a failing clear keeps the mark for the next try', () async {
    await reset().markPending();
    final r = FirestoreCacheReset(
      prefs: prefs,
      isWeb: false,
      waitForPendingWrites: () async {},
      terminate: () async {},
      clearPersistence: () async => throw StateError('instance still running'),
    );
    expect(await r.runIfPending(), isFalse);
    expect(r.isPending, isTrue);
  });

  test('concurrent callers share one run', () async {
    await reset().markPending();
    final gate = Completer<void>();
    final r = reset(wait: () => gate.future, timeout: const Duration(seconds: 2));
    final a = r.runIfPending();
    final b = r.runIfPending();
    gate.complete();
    expect(await Future.wait([a, b]), [true, true]);
    expect(calls.where((c) => c == 'clear'), hasLength(1));
  });

  test('web keeps no disk cache: no mark, no reset', () async {
    final r = reset(isWeb: true);
    await r.markPending();
    expect(prefs.getBool(FirestoreCacheReset.pendingKey), isNull);
    expect(await r.runIfPending(), isFalse);
    expect(calls, isEmpty);
  });

  group('TAS-244: cache left by an older build', () {
    test('first start of this build drops the cache once', () async {
      await reset().markLegacyCacheOnce();
      expect(await reset().runIfPending(), isTrue);
      expect(calls, ['wait', 'terminate', 'clear']);

      calls.clear();
      await reset().markLegacyCacheOnce();
      expect(await reset().runIfPending(), isFalse);
      expect(calls, isEmpty);
    });

    test('unsent writes postpone it to the next start, then it runs', () async {
      await reset().markLegacyCacheOnce();
      final pending = Completer<void>();
      expect(await reset(wait: () => pending.future).runIfPending(), isFalse);
      expect(reset().isPending, isTrue);

      await reset().markLegacyCacheOnce();
      expect(await reset().runIfPending(), isTrue);
    });

    test('web: no mark', () async {
      await reset(isWeb: true).markLegacyCacheOnce();
      expect(prefs.getBool(FirestoreCacheReset.pendingKey), isNull);
      expect(prefs.getBool(FirestoreCacheReset.legacyDoneKey), isNull);
    });
  });
}
