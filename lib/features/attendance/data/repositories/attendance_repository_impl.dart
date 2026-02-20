import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/attendance/data/datasources/attendance_local_data_source.dart';
import 'package:delegate_app/features/attendance/data/datasources/attendance_remote_data_source.dart';
import 'package:delegate_app/features/attendance/domain/entities/attendance.dart';
import 'package:delegate_app/features/attendance/domain/repositories/attendance_repository.dart';
import 'package:delegate_app/features/attendance/data/datasources/attendance_offline_queue.dart';
import 'package:delegate_app/features/attendance/data/models/attendance_model.dart';
import 'package:uuid/uuid.dart';

class AttendanceRepositoryImpl implements AttendanceRepository {
  final AttendanceRemoteDataSource remoteDataSource;
  final AttendanceLocalDataSource localDataSource;
  final AttendanceOfflineQueue offlineQueue;

  AttendanceRepositoryImpl({
    required this.remoteDataSource,
    required this.localDataSource,
    required this.offlineQueue,
  });

  @override
  Future<Either<Failure, Attendance>> checkIn(
    String userId,
    double lat,
    double long, {
    required String companyId,
    required String organizationId,
    required String deviceInfo,
    String? branchName,
  }) async {
    try {
      final result = await remoteDataSource.checkIn(
        userId,
        lat,
        long,
        companyId: companyId,
        organizationId: organizationId,
        deviceInfo: deviceInfo,
        branchName: branchName,
      );
      // Always cache attendance after successful remote write
      await localDataSource.cacheAttendance(result);
      return Right(result);
    } on Failure catch (e) {
      if (e is ServerFailure) {
        final localId = 'offline_${const Uuid().v4()}';
        final now = DateTime.now();
        await offlineQueue.addToQueue({
          'delegateId': userId,
          'companyId': companyId,
          'organizationId': organizationId,
          'deviceInfo': deviceInfo,
          'type': 'check_in',
          'location': {'latitude': lat, 'longitude': long},
          'branchName': branchName,
          'timestamp': now.toIso8601String(),
        });

        final localModel = AttendanceModel(
          id: localId,
          userId: userId,
          checkInTime: now,
          localCheckInTime: now,
          latitude: lat,
          longitude: long,
          branchName: branchName,
          isSynced: false,
        );

        await localDataSource.cacheAttendance(localModel);
        return Right(localModel);
      }
      return Left(e);
    }
  }

  @override
  Future<Either<Failure, Attendance>> checkOut(
    String attendanceId,
    double lat,
    double long,
  ) async {
    try {
      final result = await remoteDataSource.checkOut(attendanceId, lat, long);
      // Always update local cache after successful checkout
      await localDataSource.updateAttendance(result);
      return Right(result);
    } on Failure catch (e) {
      if (e is ServerFailure) {
        final now = DateTime.now();
        await offlineQueue.addToQueue({
          'type': 'check_out',
          'relatedCheckInId': attendanceId,
          'location': {'latitude': lat, 'longitude': long},
          'timestamp': now.toIso8601String(),
        });

        final history = await localDataSource.getLastAttendanceHistory();
        final index = history.indexWhere(
          (element) => element.id == attendanceId,
        );
        if (index != -1) {
          final oldModel = history[index];
          final localModel = AttendanceModel(
            id: oldModel.id,
            userId: oldModel.userId,
            checkInTime: oldModel.checkInTime,
            checkOutTime: now,
            localCheckOutTime: now,
            latitude: oldModel.latitude,
            longitude: oldModel.longitude,
            branchName: oldModel.branchName,
            isSynced: false,
          );
          await localDataSource.updateAttendance(localModel);
          return Right(localModel);
        } else {
          return const Left(
            ServerFailure('تعذر العثور على سجل الحضور محلياً.'),
          );
        }
      }
      return Left(e);
    }
  }

  @override
  Future<Either<Failure, List<Attendance>>> getHistory(String userId) async {
    try {
      final result = await remoteDataSource.getHistory(userId);
      return Right(result);
    } on Failure catch (e) {
      // On network error, fallback to local cache
      try {
        final localHistory = await localDataSource.getLastAttendanceHistory();
        if (localHistory.isNotEmpty) {
          return Right(localHistory);
        }
      } catch (_) {
        // If local also fails, return the original remote failure
      }
      return Left(e);
    }
  }

  @override
  Future<Either<Failure, Attendance?>> findActiveAttendance(
    String userId,
  ) async {
    try {
      final result = await remoteDataSource.findActiveAttendance(userId);
      return Right(result);
    } on Failure catch (e) {
      return Left(e);
    }
  }

  @override
  Future<Either<Failure, void>> syncPendingAttendance() async {
    try {
      final queue = await offlineQueue.getQueue();
      if (queue.isEmpty) {
        return const Right(null);
      }

      await remoteDataSource.syncOfflineQueue(queue);
      await offlineQueue.clearQueue();
      return const Right(null);
    } on Failure catch (e) {
      return Left(e);
    } catch (e) {
      return const Left(ServerFailure('خطأ غير متوقع أثناء المزامنة.'));
    }
  }
}
