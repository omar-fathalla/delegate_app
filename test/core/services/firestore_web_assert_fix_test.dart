import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/services/branches_session_cache.dart';
import 'package:delegate_app/core/services/firestore_client_health.dart';
import 'package:delegate_app/core/services/firestore_resilience_helper.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockQuery extends Mock implements Query<Map<String, dynamic>> {}

class _MockSnap extends Mock implements QuerySnapshot<Map<String, dynamic>> {}

class _CountingFirestore extends FakeFirebaseFirestore {
  int branchCollectionCalls = 0;
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) {
    if (path == 'branches') branchCollectionCalls++;
    return super.collection(path);
  }
}

void main() {
  setUpAll(() => registerFallbackValue(const GetOptions()));

  tearDown(() {
    FirestoreResilienceHelper.debugIsWebOverride = null;
    FirestoreClientHealth.debugIsWebOverride = null;
    FirestoreClientHealth.debugReset();
    BranchesSessionCache.invalidate();
    BranchesSessionCache.debugSessionKey = null;
  });

  group('FirestoreResilienceHelper on web', () {
    test('slow server get does not start a second overlapping get', () async {
      FirestoreResilienceHelper.debugIsWebOverride = true;
      final q = _MockQuery();
      final snap = _MockSnap();
      final completer = Completer<QuerySnapshot<Map<String, dynamic>>>();
      var inFlight = 0, maxInFlight = 0, calls = 0;
      when(() => q.get(any())).thenAnswer((_) {
        calls++;
        inFlight++;
        maxInFlight = inFlight > maxInFlight ? inFlight : maxInFlight;
        return completer.future.whenComplete(() => inFlight--);
      });
      final f = q.getResilient(timeout: const Duration(milliseconds: 10));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(calls, 1, reason: 'no fallback get while the first is pending');
      completer.complete(snap);
      expect(await f, same(snap));
      expect(maxInFlight, 1);
      final captured = verify(() => q.get(captureAny())).captured;
      expect((captured.single as GetOptions).source, Source.serverAndCache);
    });

    test('falls back to cache only after the first get failed', () async {
      FirestoreResilienceHelper.debugIsWebOverride = true;
      final q = _MockQuery();
      final snap = _MockSnap();
      when(() => q.get(any())).thenAnswer((inv) {
        final o = inv.positionalArguments.first as GetOptions;
        if (o.source == Source.cache) return Future.value(snap);
        return Future.error(FirebaseException(plugin: 'x', code: 'unavailable'));
      });
      expect(await q.getResilient(), same(snap));
    });

    test('dead client error is rethrown, not retried, and flags banner', () async {
      FirestoreResilienceHelper.debugIsWebOverride = true;
      FirestoreClientHealth.debugIsWebOverride = true;
      final q = _MockQuery();
      when(() => q.get(any())).thenAnswer((_) => Future.error(Exception(
          'FIRESTORE (12.12.0) INTERNAL ASSERTION FAILED: Unexpected state (ID: b815)')));
      await expectLater(q.getResilient(), throwsException);
      verify(() => q.get(any())).called(1);
      expect(FirestoreClientHealth.clientDead.value, isTrue);
    });
  });

  test('mobile path unchanged: server first, then cache', () async {
    FirestoreResilienceHelper.debugIsWebOverride = false;
    final q = _MockQuery();
    final snap = _MockSnap();
    when(() => q.get(any())).thenAnswer((inv) {
      final o = inv.positionalArguments.first as GetOptions;
      if (o.source == Source.server) {
        return Future.error(FirebaseException(plugin: 'x', code: 'unavailable'));
      }
      return Future.value(snap);
    });
    expect(await q.getResilient(), same(snap));
    final sources = verify(() => q.get(captureAny()))
        .captured
        .map((o) => (o as GetOptions).source)
        .toList();
    expect(sources, [Source.server, Source.cache]);
  });

  group('BranchesSessionCache', () {
    test('loads branches once per session and shares in-flight load', () async {
      BranchesSessionCache.debugSessionKey = () => 'u1';
      final fs = _CountingFirestore();
      await fs.collection('branches').add({'branchName': 'A'});
      fs.branchCollectionCalls = 0;
      final results = await Future.wait([
        BranchesSessionCache.load(fs),
        BranchesSessionCache.load(fs),
      ]);
      final again = await BranchesSessionCache.load(fs);
      expect(fs.branchCollectionCalls, 1);
      expect(results[0].single['branchName'], 'A');
      expect(again.length, 1);
    });

    test('new session (uid change) or invalidate reloads', () async {
      var uid = 'u1';
      BranchesSessionCache.debugSessionKey = () => uid;
      final fs = _CountingFirestore();
      await BranchesSessionCache.load(fs);
      uid = 'u2';
      await BranchesSessionCache.load(fs);
      BranchesSessionCache.invalidate();
      await BranchesSessionCache.load(fs);
      expect(fs.branchCollectionCalls, 3);
    });
  });

  group('FirestoreClientHealth', () {
    test('detects ca9/b815 assertion text', () {
      expect(FirestoreClientHealth.isClientDeadError(
          'FIRESTORE INTERNAL ASSERTION FAILED: Unexpected state (ID: ca9)'), isTrue);
      expect(FirestoreClientHealth.isClientDeadError('AsyncQueue is already failed'), isTrue);
      expect(FirestoreClientHealth.isClientDeadError('permission-denied'), isFalse);
      expect(FirestoreClientHealth.isClientDeadError('doc b815 not found'), isFalse);
      expect(FirestoreClientHealth.isClientDeadError('branch-ca9-id'), isFalse);
      expect(FirestoreClientHealth.isClientDeadError(
          'FIRESTORE (12.19.0) INTERNAL ASSERTION FAILED: Unexpected state (ID: b815)'), isTrue);
    });

    test('no-op on mobile', () {
      FirestoreClientHealth.debugIsWebOverride = false;
      expect(FirestoreClientHealth.report('INTERNAL ASSERTION FAILED'), isFalse);
      expect(FirestoreClientHealth.clientDead.value, isFalse);
    });

    testWidgets('banner shows reload message once client is dead', (t) async {
      FirestoreClientHealth.debugIsWebOverride = true;
      await t.pumpWidget(const MaterialApp(
          home: FirestoreClientHealthBanner(child: Text('tabs'))));
      expect(find.text(FirestoreClientHealth.reloadMessage), findsNothing);
      FirestoreClientHealth.report('INTERNAL ASSERTION FAILED (ID: ca9)');
      FirestoreClientHealth.report('INTERNAL ASSERTION FAILED (ID: b815)');
      await t.pump();
      expect(find.text(FirestoreClientHealth.reloadMessage), findsOneWidget);
      expect(find.byKey(const Key('firestoreReloadButton')), findsOneWidget);
    });
  });
}
