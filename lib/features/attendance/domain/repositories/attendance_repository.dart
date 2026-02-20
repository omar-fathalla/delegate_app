import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/attendance/domain/entities/attendance.dart';

abstract class AttendanceRepository {
  Future<Either<Failure, Attendance>> checkIn(
    String userId,
    double lat,
    double long, {
    required String companyId,
    required String organizationId,
    required String deviceInfo,
    String? branchName,
  });
  Future<Either<Failure, Attendance>> checkOut(
    String attendanceId,
    double lat,
    double long,
  );
  Future<Either<Failure, List<Attendance>>> getHistory(String userId);

  /// Finds the active attendance session (no checkOutTime) for the delegate.
  Future<Either<Failure, Attendance?>> findActiveAttendance(String userId);
}
