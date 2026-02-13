import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/attendance/data/datasources/attendance_local_data_source.dart';
import 'package:delegate_app/features/attendance/data/datasources/attendance_remote_data_source.dart';
import 'package:delegate_app/features/attendance/domain/entities/attendance.dart';
import 'package:delegate_app/features/attendance/domain/repositories/attendance_repository.dart';

class AttendanceRepositoryImpl implements AttendanceRepository {
  final AttendanceRemoteDataSource remoteDataSource;
  final AttendanceLocalDataSource localDataSource;
  final bool isDemoMode;

  AttendanceRepositoryImpl({
    required this.remoteDataSource,
    required this.localDataSource,
    this.isDemoMode = true,
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
      if (isDemoMode) {
        await localDataSource.cacheAttendance(result);
      }
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
      if (isDemoMode) {
        await localDataSource.updateAttendance(result);
      }
      return Right(result);
    } on Failure catch (e) {
      return Left(e);
    }
  }

  @override
  Future<Either<Failure, List<Attendance>>> getHistory(String userId) async {
    try {
      if (isDemoMode) {
        final localHistory = await localDataSource.getLastAttendanceHistory();
        if (localHistory.isNotEmpty) {
          return Right(localHistory);
        }
      }
      final result = await remoteDataSource.getHistory(userId);
      return Right(result);
    } on Failure catch (e) {
      return Left(e);
    }
  }
}
