import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/constants.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/attendance/data/datasources/attendance_remote_data_source.dart';
import 'package:delegate_app/features/attendance/data/models/attendance_model.dart';
import 'package:delegate_app/features/attendance/domain/attendance_action_messages.dart';
import 'package:delegate_app/features/attendance/domain/entities/attendance.dart';
import 'package:delegate_app/features/attendance/domain/usecases/check_in.dart';
import 'package:delegate_app/features/attendance/domain/usecases/check_out.dart';
import 'package:delegate_app/features/attendance/domain/usecases/get_history.dart';
import 'package:delegate_app/features/attendance/domain/usecases/get_history_paginated.dart';
import 'package:delegate_app/features/attendance/domain/usecases/sync_attendance.dart';
import 'package:delegate_app/features/attendance/presentation/attendance_action_lock.dart';
import 'package:delegate_app/features/attendance/presentation/bloc/attendance_bloc.dart';
import 'package:delegate_app/features/attendance/presentation/widgets/attendance_action_button.dart';
import 'package:delegate_app/features/attendance/presentation/widgets/early_checkout_confirm_sheet.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:fake_async/fake_async.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockCheckIn extends Mock implements CheckIn {}

class MockCheckOut extends Mock implements CheckOut {}

class MockGetHistory extends Mock implements GetHistory {}

class MockGetHistoryPaginated extends Mock implements GetHistoryPaginated {}

class MockSyncAttendance extends Mock implements SyncAttendance {}

class FakeCheckInParams extends Fake implements CheckInParams {}

class MockFirestore extends Mock implements FirebaseFirestore {}

class MockColl extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

class MockDoc extends Mock implements DocumentReference<Map<String, dynamic>> {}

/// Data source whose server-side "active session" lookup is scripted.
class ScriptedDataSource extends AttendanceRemoteDataSourceImpl {
  ScriptedDataSource({required super.firestore, required this.active});
  final Future<AttendanceModel?> Function() active;
  @override
  Future<AttendanceModel?> findActiveAttendance(
    String userId,
    String organizationId,
  ) => active();
}

final tAttendance = Attendance(
  id: 'att-1',
  userId: 'u1',
  organizationId: 'org1',
  checkInTime: DateTime(2026, 11, 2, 9),
  latitude: 30,
  longitude: 31,
  branchName: 'b1',
);

CheckInRequested checkInEvent() => const CheckInRequested(
  userId: 'u1',
  companyId: 'c1',
  organizationId: 'org1',
  deviceInfo: 'test',
  lat: 30,
  long: 31,
  branchName: 'b1',
);

Future<AttendanceModel> doCheckIn(AttendanceRemoteDataSourceImpl ds) =>
    ds.checkIn(
      'u1',
      30,
      31,
      companyId: 'c1',
      organizationId: 'org1',
      deviceInfo: 'test',
      branchName: 'b1',
    );

Widget localized(Widget child) => MaterialApp(
  locale: const Locale('ar'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  late MockCheckIn checkIn;
  late AttendanceBloc bloc;

  setUpAll(() {
    registerFallbackValue(FakeCheckInParams());
    registerFallbackValue(const GetOptions());
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    AttendanceRemoteDataSourceImpl.resetPendingAttempts();
    checkIn = MockCheckIn();
    bloc = AttendanceBloc(
      checkIn: checkIn,
      checkOut: MockCheckOut(),
      getHistory: MockGetHistory(),
      getHistoryPaginated: MockGetHistoryPaginated(),
      syncAttendance: MockSyncAttendance(),
    );
  });

  tearDown(() => bloc.close());

  group('double tap during slow GPS', () {
    test('second tap is ignored and only one check-in is sent', () async {
      final gps = Completer<void>();
      final write = Completer<Either<Failure, Attendance>>();
      when(() => checkIn(any())).thenAnswer((_) => write.future);
      final lock = AttendanceActionLock();
      var actions = 0;

      Future<void> tap() async {
        actions++;
        await gps.future; // slow GPS fix
        bloc.add(checkInEvent());
      }

      final first = lock.run(bloc: bloc, action: tap, onChanged: () {});
      expect(lock.isBusy, isTrue);
      expect(
        await lock.run(bloc: bloc, action: tap, onChanged: () {}),
        isFalse,
      );

      gps.complete();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      // Still locked: GPS done but the write hasn't returned yet.
      expect(lock.isBusy, isTrue);
      expect(
        await lock.run(bloc: bloc, action: tap, onChanged: () {}),
        isFalse,
      );

      write.complete(Right(tAttendance));
      await first;
      expect(lock.isBusy, isFalse);
      expect(actions, 1);
      verify(() => checkIn(any())).called(1);
    });

    test('bloc drops a second CheckInRequested while one is running', () async {
      final write = Completer<Either<Failure, Attendance>>();
      when(() => checkIn(any())).thenAnswer((_) => write.future);
      bloc.add(checkInEvent());
      bloc.add(checkInEvent());
      await Future<void>.delayed(const Duration(milliseconds: 10));
      write.complete(Right(tAttendance));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      verify(() => checkIn(any())).called(1);
    });
  });

  group('locked button UI', () {
    testWidgets('shows spinner + label and ignores taps', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        localized(
          AttendanceActionButton(
            isCheckedIn: false,
            isLoading: true,
            loadingLabel: 'جارٍ تحديد موقعك…',
            onTap: () => taps++,
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('جارٍ تحديد موقعك…'), findsOneWidget);
      await tester.tap(find.byType(AttendanceActionButton));
      expect(taps, 0);
    });
  });

  group('early check-out confirmation', () {
    Future<bool?> open(WidgetTester tester, Duration since) async {
      bool? result;
      final now = DateTime(2026, 11, 2, 10);
      await tester.pumpWidget(
        localized(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await confirmEarlyCheckOutIfNeeded(
                  context,
                  checkInTime: now.subtract(since),
                  now: now,
                );
              },
              child: const Text('go'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('check-out 3 min after check-in asks first; cancel = no', (
      tester,
    ) async {
      await open(tester, const Duration(minutes: 3));
      expect(find.byType(EarlyCheckOutConfirmSheet), findsOneWidget);
      expect(find.textContaining('3'), findsWidgets);
      await tester.tap(find.byKey(const Key('earlyCheckOutCancel')));
      await tester.pumpAndSettle();
      expect(find.byType(EarlyCheckOutConfirmSheet), findsNothing);
    });

    testWidgets('confirm = proceed', (tester) async {
      bool? result;
      final now = DateTime(2026, 11, 2, 10);
      await tester.pumpWidget(
        localized(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await confirmEarlyCheckOutIfNeeded(
                  context,
                  checkInTime: now.subtract(const Duration(minutes: 2)),
                  now: now,
                );
              },
              child: const Text('go'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('earlyCheckOutConfirm')));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });

    testWidgets('after 10 minutes no sheet is shown', (tester) async {
      final r = await open(tester, const Duration(minutes: 11));
      expect(find.byType(EarlyCheckOutConfirmSheet), findsNothing);
      expect(r, isTrue);
    });
  });

  group('server-only decision', () {
    test('offline: check-in writes nothing and explains', () async {
      final fs = FakeFirebaseFirestore();
      final ds = ScriptedDataSource(
        firestore: fs,
        active: () => Future.error(TimeoutException('offline')),
      );
      await expectLater(
        doCheckIn(ds),
        throwsA(
          isA<ServerFailure>().having(
            (f) => f.message,
            'message',
            kCheckInOfflineMessage,
          ),
        ),
      );
      expect((await fs.collection(kAttendanceCollection).get()).docs, isEmpty);
    });

    test('offline: check-out server read fails -> no write', () async {
      final fs = MockFirestore();
      final coll = MockColl();
      final doc = MockDoc();
      when(() => fs.collection(kAttendanceCollection)).thenReturn(coll);
      when(() => coll.doc(any())).thenReturn(doc);
      when(() => doc.get(any())).thenAnswer(
        (_) => Future.error(
          FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
        ),
      );
      final ds = AttendanceRemoteDataSourceImpl(firestore: fs);
      await expectLater(
        ds.checkOut('att-1', 'org1', 30, 31),
        throwsA(
          isA<ServerFailure>().having(
            (f) => f.message,
            'message',
            kCheckOutOfflineMessage,
          ),
        ),
      );
      verifyNever(() => fs.batch());
    });

    test(
      'repeating a check-out never adds a second check_out record',
      () async {
        final fs = FakeFirebaseFirestore();
        final ref = await fs.collection(kAttendanceCollection).add({
          'delegateId': 'u1',
          'userId': 'u1',
          'companyId': 'c1',
          'organizationId': 'org1',
          'timestamp': Timestamp.fromDate(DateTime.now()),
          'type': 'check_in',
          'location': {'latitude': 30.0, 'longitude': 31.0},
          'branchName': 'b1',
        });
        final ds = AttendanceRemoteDataSourceImpl(firestore: fs);
        await ds.checkOut(ref.id, 'org1', 30, 31);
        // Same attempt again (e.g. retry after a timeout): idempotent success.
        final again = await ds.checkOut(ref.id, 'org1', 30, 31);
        expect(again.checkOutTime, isNotNull);
        // A session closed by something else (e.g. auto-close) is refused.
        await ref.update({'checkOutDocId': 'other'});
        await expectLater(
          ds.checkOut(ref.id, 'org1', 30, 31),
          throwsA(
            isA<ServerFailure>().having(
              (f) => f.message,
              'message',
              kAlreadyCheckedOutMessage,
            ),
          ),
        );
        final outs = await fs
            .collection(kAttendanceCollection)
            .where('type', isEqualTo: 'check_out')
            .get();
        expect(outs.docs, hasLength(1));
      },
    );

    test('timeout is "unknown" and the retry reuses the same document', () {
      fakeAsync((async) {
        final fs = MockFirestore();
        final coll = MockColl();
        final auto = MockDoc();
        final doc = MockDoc();
        when(() => fs.collection(kAttendanceCollection)).thenReturn(coll);
        when(() => coll.doc()).thenReturn(auto);
        when(() => auto.id).thenReturn('A');
        when(() => coll.doc('A')).thenReturn(doc);
        when(() => doc.id).thenReturn('A');
        // The write hangs (queued offline) and the server can't confirm it.
        when(() => doc.set(any())).thenAnswer((_) => Completer<void>().future);
        when(() => doc.get(any())).thenAnswer(
          (_) => Future.error(
            FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
          ),
        );
        final ds = ScriptedDataSource(firestore: fs, active: () async => null);

        final errors = <String>[];
        for (var i = 0; i < 2; i++) {
          doCheckIn(ds).then(
            (_) {},
            onError: (Object e) {
              errors.add((e as Failure).message);
            },
          );
          async.elapse(const Duration(seconds: 30));
        }
        expect(errors, [kCheckInUnknownMessage, kCheckInUnknownMessage]);
        verify(() => coll.doc()).called(1); // one ID ever generated
        verify(() => doc.set(any())).called(2); // both writes hit doc 'A'
      });
    });

    test('a landed earlier attempt is returned instead of a 2nd check-in', () {
      fakeAsync((async) {
        final fs = MockFirestore();
        final coll = MockColl();
        final auto = MockDoc();
        final doc = MockDoc();
        when(() => fs.collection(kAttendanceCollection)).thenReturn(coll);
        when(() => coll.doc()).thenReturn(auto);
        when(() => auto.id).thenReturn('A');
        when(() => coll.doc('A')).thenReturn(doc);
        when(() => doc.set(any())).thenAnswer((_) => Completer<void>().future);
        when(() => doc.get(any())).thenAnswer(
          (_) => Future.error(
            FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
          ),
        );
        AttendanceModel? active;
        final ds = ScriptedDataSource(
          firestore: fs,
          active: () async => active,
        );

        doCheckIn(ds).then((_) {}, onError: (_) {});
        async.elapse(const Duration(seconds: 30));
        // The queued write reaches the server before the retry.
        active = AttendanceModel(
          id: 'A',
          userId: 'u1',
          organizationId: 'org1',
          checkInTime: DateTime.now(),
          latitude: 30,
          longitude: 31,
          branchName: 'b1',
        );
        AttendanceModel? result;
        doCheckIn(ds).then((r) => result = r);
        async.elapse(const Duration(seconds: 1));
        expect(result?.id, 'A');
        verify(() => doc.set(any())).called(1);
      });
    });
  });
}
