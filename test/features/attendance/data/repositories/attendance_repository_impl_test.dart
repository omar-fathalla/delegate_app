import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/attendance/data/datasources/attendance_local_data_source.dart';
import 'package:delegate_app/features/attendance/data/datasources/attendance_offline_queue.dart';
import 'package:delegate_app/features/attendance/data/datasources/attendance_remote_data_source.dart';
import 'package:delegate_app/features/attendance/data/models/attendance_model.dart';
import 'package:delegate_app/core/models/pagination_response.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/attendance/attendance_branch_resolve.dart';
import 'package:delegate_app/features/attendance/data/repositories/attendance_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:delegate_app/core/services/trusted_time_anchor.dart';
import 'package:delegate_app/features/admin/domain/entities/branch.dart';
import 'package:delegate_app/features/attendance/data/datasources/attendance_server_api.dart';
import 'package:delegate_app/features/attendance/data/datasources/offline_branch_cache.dart';
import 'package:delegate_app/features/attendance/domain/attendance_action_messages.dart';
import 'package:delegate_app/features/attendance/domain/entities/attendance.dart';

// --- Mock Remote Data Source ---
class MockAttendanceRemoteDataSource implements AttendanceRemoteDataSource {
  Future<AttendanceModel> Function(
    String,
    double,
    double, {
    required String companyId,
    required String organizationId,
    required String deviceInfo,
    String? branchName,
    String? branchId,
    String? branchOrganizationUID,
    String? delegateName,
    String? phoneNumber,
    String? companyName,
    String? personalPhotoURL,
  })?
  checkInStub;
  Future<AttendanceModel> Function(String, String, double, double)?
  checkOutStub;
  Future<List<AttendanceModel>> Function(String, String)? getHistoryStub;
  Future<PaginationResponse<AttendanceModel>> Function(
    String,
    String, {
    int limit,
    DocumentSnapshot? startAfter,
  })?
  getHistoryPaginatedStub;
  Future<AttendanceModel?> Function(String, String)? findActiveAttendanceStub;
  Future<void> Function(OfflineAttendanceAction)? sendOfflineActionStub;
  final List<OfflineAttendanceAction> sentOffline = [];
  Future<Map<String, dynamic>?> Function(String)? getBranchByNameStub;
  Future<ResolvedBranchDocument?> Function({
    String? branchId,
    String? organizationUID,
    String? branchName,
  })? resolveBranchStub;
  Future<void> Function({
    required String branchName,
    required double latitude,
    required double longitude,
    required double geofenceRadius,
    String? branchId,
    String? organizationUID,
  })?
  saveBranchStub;

  int getHistoryCallCount = 0;
  int syncCallCount = 0;

  @override
  Future<AttendanceModel> checkIn(
    String userId,
    double lat,
    double long, {
    required String companyId,
    required String organizationId,
    required String deviceInfo,
    String? branchName,
    String? branchId,
    String? branchOrganizationUID,
    String? delegateName,
    String? phoneNumber,
    String? companyName,
    String? personalPhotoURL,
    Map<String, dynamic>? qrProof,
  }) {
    if (checkInStub != null) {
      return checkInStub!(
        userId,
        lat,
        long,
        companyId: companyId,
        organizationId: organizationId,
        deviceInfo: deviceInfo,
        branchName: branchName,
        branchId: branchId,
        branchOrganizationUID: branchOrganizationUID,
        delegateName: delegateName,
        phoneNumber: phoneNumber,
        companyName: companyName,
        personalPhotoURL: personalPhotoURL,
      );
    }
    throw UnimplementedError();
  }

  @override
  Future<AttendanceModel> checkOut(
    String attendanceId,
    String organizationId,
    double lat,
    double long,
  ) {
    if (checkOutStub != null) {
      return checkOutStub!(attendanceId, organizationId, lat, long);
    }
    throw UnimplementedError();
  }

  @override
  Future<List<AttendanceModel>> getHistory(
    String userId,
    String organizationId, {
    String? nationalityID,
    String? phoneNumber,
  }) {
    getHistoryCallCount++;
    if (getHistoryStub != null) return getHistoryStub!(userId, organizationId);
    throw UnimplementedError();
  }

  @override
  Future<List<AttendanceModel>> getHistoryForMonth(
    String userId, {
    required DateTime month,
    String? nationalityID,
    String? phoneNumber,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<PaginationResponse<AttendanceModel>> getHistoryPaginated(
    String userId,
    String organizationId, {
    int limit = 20,
    String? nationalityID,
    String? phoneNumber,
    DocumentSnapshot? startAfter,
  }) {
    if (getHistoryPaginatedStub != null) {
      return getHistoryPaginatedStub!(
        userId,
        organizationId,
        limit: limit,
        startAfter: startAfter,
      );
    }
    throw UnimplementedError();
  }

  @override
  Future<List<AttendanceModel>> getRecentSessionsAcrossOrgs(
    String userId, {
    String? nationalityID,
    String? phoneNumber,
    int limit = 6,
  }) async => [];

  @override
  Future<AttendanceModel?> findActiveAttendance(
    String userId,
    String organizationId,
  ) {
    if (findActiveAttendanceStub != null) {
      return findActiveAttendanceStub!(userId, organizationId);
    }
    throw UnimplementedError();
  }

  @override
  Future<void> sendOfflineAction(OfflineAttendanceAction action) async {
    syncCallCount++;
    if (sendOfflineActionStub != null) await sendOfflineActionStub!(action);
    sentOffline.add(action);
  }

  @override
  Future<Map<String, dynamic>?> getBranchByName(String branchName) {
    if (getBranchByNameStub != null) return getBranchByNameStub!(branchName);
    throw UnimplementedError();
  }

  @override
  Future<ResolvedBranchDocument?> resolveBranch({
    String? branchId,
    String? organizationUID,
    String? branchName,
  }) {
    if (resolveBranchStub != null) {
      return resolveBranchStub!(
        branchId: branchId,
        organizationUID: organizationUID,
        branchName: branchName,
      );
    }
    throw UnimplementedError();
  }

  @override
  Future<void> saveBranch({
    required String branchName,
    required double latitude,
    required double longitude,
    required double geofenceRadius,
    String? branchId,
    String? organizationUID,
  }) {
    if (saveBranchStub != null) {
      return saveBranchStub!(
        branchName: branchName,
        latitude: latitude,
        longitude: longitude,
        geofenceRadius: geofenceRadius,
      );
    }
    throw UnimplementedError();
  }

  @override
  Stream<AttendanceModel?> streamActiveAttendance(
    String userId,
    String organizationId,
  ) {
    return const Stream.empty();
  }
}

// --- Mock Local Data Source ---
class MockAttendanceLocalDataSource implements AttendanceLocalDataSource {
  List<AttendanceModel> history = [];
  int cacheCallCount = 0;
  int overwriteCallCount = 0;

  @override
  Future<void> cacheAttendance(
    AttendanceModel attendanceToCache, [
    String? organizationId,
    String? userId,
  ]) async {
    cacheCallCount++;
    history.add(attendanceToCache);
  }

  @override
  Future<List<AttendanceModel>> getLastAttendanceHistory([
    String? organizationId,
    String? userId,
  ]) async {
    return history;
  }

  @override
  Future<void> updateAttendance(
    AttendanceModel attendanceToUpdate, [
    String? organizationId,
    String? userId,
  ]) async {
    final index = history.indexWhere((e) => e.id == attendanceToUpdate.id);
    if (index != -1) history[index] = attendanceToUpdate;
  }

  @override
  Future<void> overwriteHistory(
    List<AttendanceModel> newHistory, [
    String? organizationId,
    String? userId,
  ]) async {
    overwriteCallCount++;
    history = List.from(newHistory);
  }

  @override
  Future<void> clearAttendanceCache([String? userId]) async {
    history.clear();
  }
}

void main() {
  late AttendanceRepositoryImpl repository;
  late MockAttendanceRemoteDataSource mockRemote;
  late MockAttendanceLocalDataSource mockLocal;
  late AttendanceOfflineQueueImpl mockQueue;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    mockRemote = MockAttendanceRemoteDataSource();
    mockLocal = MockAttendanceLocalDataSource();
    mockQueue = AttendanceOfflineQueueImpl(
      sharedPreferences: await SharedPreferences.getInstance(),
    );
    repository = AttendanceRepositoryImpl(
      remoteDataSource: mockRemote,
      localDataSource: mockLocal,
      offlineQueue: mockQueue,
    );
  });

  final tCheckInTime = DateTime(2024, 6, 15, 9, 0);
  final tAttendance = AttendanceModel(
    id: 'a1',
    userId: 'u1',
    organizationId: 'org1',
    checkInTime: tCheckInTime,
    latitude: 30.0444,
    longitude: 31.2357,
    branchName: 'الفرع الرئيسي',
  );

  group('getHistory', () {
    test('should return history from remote on success', () async {
      mockRemote.getHistoryStub = (userId, orgId) async => [tAttendance];

      final result = await repository.getHistory('u1', 'org1');

      expect(mockRemote.getHistoryCallCount, 1);
      result.fold((failure) => fail('Should have returned Right'), (history) {
        expect(history.length, 1);
        expect(history.first.id, 'a1');
      });
    });

    test('should cache remote history locally', () async {
      mockRemote.getHistoryStub = (userId, orgId) async => [tAttendance];

      await repository.getHistory('u1', 'org1');

      expect(mockLocal.overwriteCallCount, 1);
    });
  });

  group('syncPendingAttendance', () {
    test('nothing queued: nothing sent', () async {
      final result = await repository.syncPendingAttendance(userId: 'u1');

      expect(result, equals(const Right(null)));
      expect(mockRemote.syncCallCount, 0);
    });

    test('no user: nothing sent', () async {
      final result = await repository.syncPendingAttendance();
      expect(result, equals(const Right(null)));
      expect(mockRemote.syncCallCount, 0);
    });
  });

  group('findActiveAttendance', () {
    test('should return attendance when found', () async {
      mockRemote.findActiveAttendanceStub = (userId, orgId) async =>
          tAttendance;

      final result = await repository.findActiveAttendance('u1', 'org1');

      result.fold(
        (failure) => fail('Should have returned Right'),
        (attendance) => expect(attendance, equals(tAttendance)),
      );
    });

    test('should return Right(null) when no active attendance', () async {
      mockRemote.findActiveAttendanceStub = (userId, orgId) async => null;

      final result = await repository.findActiveAttendance('u1', 'org1');

      result.fold(
        (failure) => fail('Should have returned Right'),
        (attendance) => expect(attendance, isNull),
      );
    });
  });

  group('saveBranch', () {
    test('should return Right(null) on success', () async {
      mockRemote.saveBranchStub =
          ({
            required String branchName,
            required double latitude,
            required double longitude,
            required double geofenceRadius,
            String? branchId,
            String? organizationUID,
          }) async {};

      final result = await repository.saveBranch(
        branchName: 'فرع جديد',
        latitude: 30.0,
        longitude: 31.0,
        geofenceRadius: 200.0,
      );

      expect(result, equals(const Right(null)));
    });

    test(
      'should return Left(Failure) when data source throws Failure',
      () async {
        const tFailure = ServerFailure('Save failed');
        mockRemote.saveBranchStub =
            ({
              required String branchName,
              required double latitude,
              required double longitude,
              required double geofenceRadius,
              String? branchId,
              String? organizationUID,
            }) => throw tFailure;

        final result = await repository.saveBranch(
          branchName: 'فرع جديد',
          latitude: 30.0,
          longitude: 31.0,
          geofenceRadius: 200.0,
        );

        expect(result, equals(const Left(tFailure)));
      },
    );
  });

  // TAS-333: two chains with a branch at the same place. The QR check-in
  // checks and records the scanned branch only.
  group('checkIn with a scanned QR branch (TAS-333)', () {
    const ownOrg = 'seed-fake-tas112-org';
    const foreignOrg = 'seed-fake-hr-org';
    Map<String, dynamic> branchDoc(String org, String name, num radius) => {
          'branchName': name,
          'organizationUID': org,
          'latitude': 30.1001,
          'longitude': 31.2001,
          'geofenceRadius': radius,
        };

    late List<Map<String, String?>> resolveCalls;
    late Map<String, String?> written;

    void stubBranches({required num ownRadius}) {
      resolveCalls = [];
      mockRemote.resolveBranchStub = ({
        String? branchId,
        String? organizationUID,
        String? branchName,
      }) async {
        resolveCalls.add({'id': branchId, 'org': organizationUID});
        if (branchId == 'seed-fake-tas112-br-qr' && organizationUID == ownOrg) {
          return ResolvedBranchDocument(
            documentId: branchId!,
            data: branchDoc(ownOrg, 'Fake Branch QR', ownRadius),
          );
        }
        if (branchId == 'seed-fake-br-alpha' && organizationUID == foreignOrg) {
          return ResolvedBranchDocument(
            documentId: branchId!,
            data: branchDoc(foreignOrg, 'Fake Branch Alpha', 100),
          );
        }
        return null;
      };
      mockRemote.checkInStub = (
        String userId,
        double lat,
        double long, {
        required String companyId,
        required String organizationId,
        required String deviceInfo,
        String? branchName,
        String? branchId,
        String? branchOrganizationUID,
        String? delegateName,
        String? phoneNumber,
        String? companyName,
        String? personalPhotoURL,
        Map<String, dynamic>? qrProof,
      }) async {
        written = {
          'organizationId': organizationId,
          'branchId': branchId,
          'branchOrganizationUID': branchOrganizationUID,
          'branchName': branchName,
        };
        return AttendanceModel(
          id: 'log1',
          userId: userId,
          organizationId: organizationId,
          checkInTime: DateTime(2026, 11, 25, 9),
          latitude: lat,
          longitude: long,
          branchName: branchName,
          branchId: branchId,
          branchOrganizationUID: branchOrganizationUID,
        );
      };
    }

    // ~200 m north of both branches: outside Alpha (150), inside 300 + 50.
    Future<Either<Failure, dynamic>> scanOwnQr() => repository.checkIn(
          'seed-fake-tas320-pro',
          30.1019,
          31.2001,
          companyId: 'seed-fake-tas112-co',
          organizationId: ownOrg,
          deviceInfo: 'test',
          branchName: 'Fake Branch QR',
          branchId: 'seed-fake-tas112-br-qr',
          branchOrganizationUID: ownOrg,
        );

    test('records the scanned branch and checks its own radius', () async {
      stubBranches(ownRadius: 300);
      final result = await scanOwnQr();
      expect(result.isRight(), isTrue, reason: '$result');
      expect(resolveCalls, [
        {'id': 'seed-fake-tas112-br-qr', 'org': ownOrg},
      ]);
      expect(written, {
        'organizationId': ownOrg,
        'branchId': 'seed-fake-tas112-br-qr',
        'branchOrganizationUID': ownOrg,
        'branchName': 'Fake Branch QR',
      });
    });

    test('out of range message uses the scanned branch radius', () async {
      stubBranches(ownRadius: 120);
      final result = await scanOwnQr();
      result.fold(
        (f) => expect(f.message, contains('170')),
        (_) => fail('should be out of range'),
      );
      expect(resolveCalls.single['id'], 'seed-fake-tas112-br-qr');
    });
  });

  // --- TAS-363: attendance without network ---
  group('offline (TAS-363)', () {
    late SharedPreferences prefs;
    late OfflineBranchCache branchCache;
    late bool online;
    late OfflineTimeCapture time;
    late AttendanceRepositoryImpl offlineRepo;
    var ids = 0;

    setUp(() async {
      prefs = await SharedPreferences.getInstance();
      branchCache = OfflineBranchCache(prefs);
      await branchCache.saveAll('org1', const [
        Branch(
          id: 'b1',
          branchName: 'فرع تجريبي',
          latitude: 30.0444,
          longitude: 31.2357,
          geofenceRadius: 100,
          organizationUID: 'org1',
        ),
      ]);
      online = false;
      ids = 0;
      time = OfflineTimeCapture(
        atMs: DateTime(2026, 11, 28, 9).millisecondsSinceEpoch,
        trusted: true,
        syncedAtMs: DateTime(2026, 11, 28, 7).millisecondsSinceEpoch,
      );
      offlineRepo = AttendanceRepositoryImpl(
        remoteDataSource: mockRemote,
        localDataSource: mockLocal,
        offlineQueue: mockQueue,
        branchCache: branchCache,
        captureTime: () => time,
        hasConnection: () async => online,
        newId: () => 'key-${++ids}-0000',
      );
    });

    Future<Either<Failure, Attendance>> checkIn({
      double lat = 30.0449,
      String? branchId = 'b1',
    }) => offlineRepo.checkIn(
      'u1',
      lat,
      31.2357,
      companyId: 'c1',
      organizationId: 'org1',
      deviceInfo: 'test',
      branchName: 'فرع تجريبي',
      branchId: branchId,
      branchOrganizationUID: 'org1',
    );

    test(
      'check-in without network is saved on the phone with the trusted time',
      () async {
        final result = await checkIn();
        final a = result.getOrElse(() => throw 'left: $result');
        expect(a.isSynced, isFalse);
        expect(a.id, 'key-1-0000');
        expect(a.checkInTime, time.at);
        final queued = mockQueue.pending('u1').single;
        expect(queued.isCheckIn, isTrue);
        expect(queued.timeTrusted, isTrue);
        expect(queued.checkIn['branchId'], 'b1');
        expect(mockRemote.syncCallCount, 0);
      },
    );

    test(
      'a branch found by name gets its id from the saved coordinates',
      () async {
        final result = await checkIn(branchId: null);
        expect(result.isRight(), isTrue);
        expect(mockQueue.pending('u1').single.checkIn['branchId'], 'b1');
      },
    );

    test('outside the saved branch: refused, nothing queued', () async {
      final result = await checkIn(lat: 30.06);
      expect(result.isLeft(), isTrue);
      expect(mockQueue.pendingCount('u1'), 0);
    });

    test(
      'branch never seen with network: clear message, nothing queued',
      () async {
        final result = await offlineRepo.checkIn(
          'u1',
          30.0449,
          31.2357,
          companyId: 'c1',
          organizationId: 'org1',
          deviceInfo: 'test',
          branchName: 'فرع تاني',
          branchId: 'b9',
          branchOrganizationUID: 'org1',
        );
        expect(result, const Left(ServerFailure(kOfflineBranchUnknownMessage)));
      },
    );

    test('a second offline check-in while one is open is refused', () async {
      await checkIn();
      expect(
        await checkIn(),
        const Left(ServerFailure(kOfflineOpenSessionMessage)),
      );
    });

    test(
      'offline check-out links to the offline check-in and shows in history',
      () async {
        final a = (await checkIn()).getOrElse(() => throw 'left');
        time = OfflineTimeCapture(
          atMs: time.atMs + 3600000,
          trusted: true,
          syncedAtMs: time.syncedAtMs,
        );
        final out = await offlineRepo.checkOut(
          a.id,
          30.0444,
          31.2357,
          userId: 'u1',
          organizationId: 'org1',
        );
        final closed = out.getOrElse(() => throw 'left');
        expect(closed.checkOutTime, time.at);
        expect(closed.isSynced, isFalse);
        final q = mockQueue.pending('u1');
        expect(q.map((x) => x.id), ['key-1-0000', 'key-1-0000_out']);
        expect(q.last.attendanceId, 'key-1-0000');
        // Same check-out again: not queued twice.
        await offlineRepo.checkOut(
          a.id,
          30.0444,
          31.2357,
          userId: 'u1',
          organizationId: 'org1',
        );
        expect(mockQueue.pendingCount('u1'), 2);

        final page = await offlineRepo.getHistoryPaginated('u1', '');
        final items = page.getOrElse(() => throw 'left').items;
        expect(items.single.id, 'key-1-0000');
        expect(items.single.checkOutTime, time.at);
      },
    );

    test(
      'sync sends in order and removes each item after its success only',
      () async {
        await checkIn();
        await offlineRepo.checkOut(
          'key-1-0000',
          30.0444,
          31.2357,
          userId: 'u1',
          organizationId: 'org1',
        );
        online = true;
        var calls = 0;
        mockRemote.sendOfflineActionStub = (a) async {
          calls++;
          if (calls == 2) throw const AttendanceServerUncertain();
        };
        final first = await offlineRepo.syncPendingAttendance(userId: 'u1');
        expect(first, const Left(NetworkFailure(kOfflineSyncRetryMessage)));
        expect(mockQueue.pending('u1').map((a) => a.id), ['key-1-0000_out']);

        mockRemote.sendOfflineActionStub = null;
        final second = await offlineRepo.syncPendingAttendance(userId: 'u1');
        expect(second, const Right(null));
        expect(mockQueue.pendingCount('u1'), 0);
        expect(mockRemote.sentOffline.map((a) => a.id), [
          'key-1-0000',
          'key-1-0000_out',
        ]);
      },
    );

    test(
      'a refused check-in is dropped with its check-out, and the delegate told why',
      () async {
        await checkIn();
        await offlineRepo.checkOut(
          'key-1-0000',
          30.0444,
          31.2357,
          userId: 'u1',
          organizationId: 'org1',
        );
        online = true;
        mockRemote.sendOfflineActionStub = (a) async {
          throw const AttendanceServerRefused(
            'إنت برّه نطاق الفرع.',
            reason: 'outside_branch',
          );
        };
        final result = await offlineRepo.syncPendingAttendance(userId: 'u1');
        expect(
          result,
          Left(
            OfflineAttendanceRejected(
              offlineRecordRejectedMessage('إنت برّه نطاق الفرع.'),
            ),
          ),
        );
        expect(mockQueue.pendingCount('u1'), 0);
        expect(mockRemote.syncCallCount, 1);
      },
    );

    test(
      'outside the branch (GeofenceOutsideFailure, TAS-397) is dropped too',
      () async {
        await checkIn();
        online = true;
        // attendanceServerError maps reason outside_branch to this type.
        mockRemote.sendOfflineActionStub = (a) async {
          throw attendanceServerError('failed-precondition', {
            'reason': 'outside_branch',
            'message': 'إنت برّه نطاق الفرع.',
            'distanceMeters': 300,
            'allowedMeters': 100,
          }, null);
        };
        final result = await offlineRepo.syncPendingAttendance(userId: 'u1');
        expect(
          result,
          Left(
            OfflineAttendanceRejected(
              offlineRecordRejectedMessage('إنت برّه نطاق الفرع.'),
            ),
          ),
        );
        expect(mockQueue.pendingCount('u1'), 0);
      },
    );

    test('signed out / other failures keep the queue', () async {
      await checkIn();
      online = true;
      mockRemote.sendOfflineActionStub = (a) async =>
          throw const ServerFailure('سجّل دخول الأول.');
      await offlineRepo.syncPendingAttendance(userId: 'u1');
      expect(mockQueue.pendingCount('u1'), 1);
    });

    test('no network: sync does not try', () async {
      await checkIn();
      final result = await offlineRepo.syncPendingAttendance(userId: 'u1');
      expect(result.isLeft(), isTrue);
      expect(mockRemote.syncCallCount, 0);
      expect(mockQueue.pendingCount('u1'), 1);
    });

    test('online check-in first sends what is queued', () async {
      await checkIn();
      await offlineRepo.checkOut(
        'key-1-0000',
        30.0444,
        31.2357,
        userId: 'u1',
        organizationId: 'org1',
      );
      online = true;
      mockRemote.resolveBranchStub =
          ({branchId, organizationUID, branchName}) async =>
              const ResolvedBranchDocument(
                documentId: 'b1',
                data: {
                  'branchName': 'فرع تجريبي',
                  'latitude': 30.0444,
                  'longitude': 31.2357,
                  'geofenceRadius': 100,
                },
              );
      mockRemote.checkInStub =
          (
            u,
            lat,
            lng, {
            required companyId,
            required organizationId,
            required deviceInfo,
            branchName,
            branchId,
            branchOrganizationUID,
            delegateName,
            phoneNumber,
            companyName,
            personalPhotoURL,
          }) async => tAttendance;
      final result = await checkIn();
      expect(result.isRight(), isTrue);
      expect(mockRemote.sentOffline.length, 2);
      expect(mockQueue.pendingCount('u1'), 0);
    });
  });
}
