import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/attendance/data/datasources/attendance_local_data_source.dart';
import 'package:delegate_app/features/attendance/data/datasources/attendance_offline_queue.dart';
import 'package:delegate_app/features/attendance/data/datasources/attendance_remote_data_source.dart';
import 'package:delegate_app/features/attendance/data/models/attendance_model.dart';
import 'package:delegate_app/features/attendance/data/repositories/attendance_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';

class MockAttendanceRemoteDataSource implements AttendanceRemoteDataSource {
  Object? throwOnCheckIn;
  Object? throwOnCheckOut;
  Object? throwOnGetHistory;
  Object? throwOnFindActiveAttendance;
  Object? throwOnSaveBranch;
  Object? throwOnSyncOfflineQueue;
  Map<String, dynamic>? getBranchByNameResult;

  @override
  Future<AttendanceModel> checkIn(String userId, double lat, double long, {required String companyId, required String organizationId, required String deviceInfo, String? branchName}) async {
    if (throwOnCheckIn != null) throw throwOnCheckIn!;
    return AttendanceModel(id: '1', userId: '1', checkInTime: DateTime.now(), latitude: 0, longitude: 0, branchName: 'n');
  }

  @override
  Future<AttendanceModel> checkOut(String attendanceId, double lat, double long) async {
    if (throwOnCheckOut != null) throw throwOnCheckOut!;
    return AttendanceModel(id: '1', userId: '1', checkInTime: DateTime.now(), latitude: 0, longitude: 0, branchName: 'n');
  }

  @override
  Future<List<AttendanceModel>> getHistory(String userId) async {
    if (throwOnGetHistory != null) throw throwOnGetHistory!;
    return [];
  }

  @override
  Future<AttendanceModel?> findActiveAttendance(String userId) async {
    if (throwOnFindActiveAttendance != null) throw throwOnFindActiveAttendance!;
    return null;
  }

  @override
  Future<void> saveBranch({required String branchName, required double latitude, required double longitude, required double geofenceRadius}) async {
    if (throwOnSaveBranch != null) throw throwOnSaveBranch!;
  }

  @override
  Future<void> syncOfflineQueue(List<Map<String, dynamic>> queue) async {
    if (throwOnSyncOfflineQueue != null) throw throwOnSyncOfflineQueue!;
  }

  @override
  Future<Map<String, dynamic>?> getBranchByName(String branchName) async {
    return getBranchByNameResult;
  }
}

class MockAttendanceLocalDataSource implements AttendanceLocalDataSource {
  Object? throwOnCacheAttendance;
  Object? throwOnUpdateAttendance;
  Object? throwOnOverwriteHistory;
  Object? throwOnGetLastAttendanceHistory;

  @override
  Future<void> cacheAttendance(AttendanceModel attendance) async {
    if (throwOnCacheAttendance != null) throw throwOnCacheAttendance!;
  }

  @override
  Future<void> updateAttendance(AttendanceModel attendance) async {
    if (throwOnUpdateAttendance != null) throw throwOnUpdateAttendance!;
  }

  @override
  Future<void> overwriteHistory(List<AttendanceModel> history) async {
    if (throwOnOverwriteHistory != null) throw throwOnOverwriteHistory!;
  }

  @override
  Future<List<AttendanceModel>> getLastAttendanceHistory() async {
    if (throwOnGetLastAttendanceHistory != null) throw throwOnGetLastAttendanceHistory!;
    return [];
  }
}

class MockAttendanceOfflineQueue implements AttendanceOfflineQueue {
  Object? throwOnGetQueue;
  Object? throwOnClearQueue;

  @override
  Future<List<Map<String, dynamic>>> getQueue() async {
    if (throwOnGetQueue != null) throw throwOnGetQueue!;
    return [];
  }

  @override
  Future<void> clearQueue() async {
    if (throwOnClearQueue != null) throw throwOnClearQueue!;
  }

  @override
  Future<void> addToQueue(Map<String, dynamic> action) async {
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

  group('checkIn', () {
    test('should return Failure when checkIn fails', () async {
      const tFailure = ServerFailure('Server Error');
      mockRemote.throwOnCheckIn = tFailure;
      // Assume internet connection is true by default
      final result = await repository.checkIn('1', 0, 0, companyId: '1', organizationId: '1', deviceInfo: '1');
      expect(result, equals(const Left(tFailure)));
    });
  });

  group('checkOut', () {
    test('should return ServerFailure when checkOut fails with generic exception', () async {
      mockRemote.throwOnCheckOut = Exception('Unexpected Error');
      final result = await repository.checkOut('1', 0, 0, userId: '1');
      expect(result.fold((l) => l, (r) => null), isA<ServerFailure>());
    });

    test('should return Failure when checkOut fails with Failure', () async {
      const tFailure = ServerFailure('Server Error');
      mockRemote.throwOnCheckOut = tFailure;
      final result = await repository.checkOut('1', 0, 0, userId: '1');
      expect(result, equals(const Left(tFailure)));
    });
  });

  group('getHistory', () {
    test('should return failure when getHistory fails and local history fails', () async {
      const tFailure = ServerFailure('Server Error');
      mockRemote.throwOnGetHistory = tFailure;
      mockLocal.throwOnGetLastAttendanceHistory = Exception('Local Error');
      final result = await repository.getHistory('1');
      expect(result, equals(const Left(tFailure)));
    });
  });

  group('findActiveAttendance', () {
    test('should return failure when findActiveAttendance fails', () async {
      const tFailure = ServerFailure('Server Error');
      mockRemote.throwOnFindActiveAttendance = tFailure;
      final result = await repository.findActiveAttendance('1');
      expect(result, equals(const Left(tFailure)));
    });
  });

  group('syncPendingAttendance', () {
    test('should return failure when getQueue throws Failure', () async {
      const tFailure = ServerFailure('Server Error');
      mockQueue.throwOnGetQueue = tFailure;
      final result = await repository.syncPendingAttendance();
      expect(result, equals(const Left(tFailure)));
    });

    test('should return ServerFailure when getQueue throws Exception', () async {
      mockQueue.throwOnGetQueue = Exception('Generic Error');
      final result = await repository.syncPendingAttendance();
      expect(result.fold((l) => l, (r) => null), isA<ServerFailure>());
    });
  });

  group('saveBranch', () {
    test('should return failure when saveBranch throws Failure', () async {
      const tFailure = ServerFailure('Server Error');
      mockRemote.throwOnSaveBranch = tFailure;
      final result = await repository.saveBranch(branchName: 'n', latitude: 0, longitude: 0, geofenceRadius: 0);
      expect(result, equals(const Left(tFailure)));
    });

    test('should return ServerFailure when saveBranch throws Exception', () async {
      mockRemote.throwOnSaveBranch = Exception('Generic Error');
      final result = await repository.saveBranch(branchName: 'n', latitude: 0, longitude: 0, geofenceRadius: 0);
      expect(result.fold((l) => l, (r) => null), isA<ServerFailure>());
    });
  });
}
