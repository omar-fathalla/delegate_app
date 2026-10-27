import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/attendance/data/datasources/attendance_local_data_source.dart';
import 'package:delegate_app/features/attendance/data/datasources/attendance_offline_queue.dart';
import 'package:delegate_app/features/attendance/data/datasources/attendance_remote_data_source.dart';
import 'package:delegate_app/features/attendance/data/models/attendance_model.dart';
import 'package:delegate_app/core/models/pagination_response.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/features/attendance/data/repositories/attendance_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';

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
  Future<void> Function(List<Map<String, dynamic>>)? syncOfflineQueueStub;
  Future<Map<String, dynamic>?> Function(String)? getBranchByNameStub;
  Future<void> Function({
    required String branchName,
    required double latitude,
    required double longitude,
    required double geofenceRadius,
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
    String? delegateName,
    String? phoneNumber,
    String? companyName,
    String? personalPhotoURL,
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
  Future<void> syncOfflineQueue(List<Map<String, dynamic>> queue) {
    syncCallCount++;
    if (syncOfflineQueueStub != null) return syncOfflineQueueStub!(queue);
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>?> getBranchByName(String branchName) {
    if (getBranchByNameStub != null) return getBranchByNameStub!(branchName);
    throw UnimplementedError();
  }

  @override
  Future<void> saveBranch({
    required String branchName,
    required double latitude,
    required double longitude,
    required double geofenceRadius,
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

// --- Mock Offline Queue ---
class MockAttendanceOfflineQueue implements AttendanceOfflineQueue {
  List<Map<String, dynamic>> queue = [];
  int clearCallCount = 0;

  @override
  Future<void> addToQueue(Map<String, dynamic> action) async {
    queue.add(action);
  }

  @override
  Future<List<Map<String, dynamic>>> getQueue() async {
    return queue;
  }

  @override
  Future<void> clearQueue() async {
    clearCallCount++;
    queue.clear();
  }
}

void main() {
  late AttendanceRepositoryImpl repository;
  late MockAttendanceRemoteDataSource mockRemote;
  late MockAttendanceLocalDataSource mockLocal;
  late MockAttendanceOfflineQueue mockQueue;

  setUp(() {
    mockRemote = MockAttendanceRemoteDataSource();
    mockLocal = MockAttendanceLocalDataSource();
    mockQueue = MockAttendanceOfflineQueue();
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
    test('should return Right(null) when queue is empty', () async {
      final result = await repository.syncPendingAttendance();

      expect(result, equals(const Right(null)));
      expect(mockRemote.syncCallCount, 0);
    });

    test('should sync queue and clear it on success', () async {
      mockQueue.queue = [
        {'action': 'check_in', 'userId': 'u1'},
      ];
      mockRemote.syncOfflineQueueStub = (_) async {};

      final result = await repository.syncPendingAttendance();

      expect(result, equals(const Right(null)));
      expect(mockRemote.syncCallCount, 1);
      expect(mockQueue.clearCallCount, 1);
    });

    test('should return Left(Failure) when sync throws Failure', () async {
      mockQueue.queue = [
        {'action': 'check_in'},
      ];
      const tFailure = ServerFailure('Sync failed');
      mockRemote.syncOfflineQueueStub = (_) => throw tFailure;

      final result = await repository.syncPendingAttendance();

      expect(result, equals(const Left(tFailure)));
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
}
