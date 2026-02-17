import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/attendance/data/datasources/attendance_local_data_source.dart';
import 'package:delegate_app/features/attendance/data/datasources/attendance_remote_data_source.dart';
import 'package:delegate_app/features/attendance/domain/entities/attendance.dart';
import 'package:delegate_app/features/attendance/domain/repositories/attendance_repository.dart';

class AttendanceRepositoryImpl implements AttendanceRepository {
  final AttendanceRemoteDataSource remoteDataSource;
  final AttendanceLocalDataSource localDataSource;

  AttendanceRepositoryImpl({
    required this.remoteDataSource,
    required this.localDataSource,
  });

  @override
  Future<Either<Failure, Attendance>> checkIn(
    String userId,
    double lat,
    double long, {
    String? branchName,
  }) async {
    try {
      final result = await remoteDataSource.checkIn(
        userId,
        lat,
        long,
        branchName: branchName,
      );
      // Always cache attendance after successful remote write
      await localDataSource.cacheAttendance(result);
      return Right(result);
    } on Failure catch (e) {
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
}
