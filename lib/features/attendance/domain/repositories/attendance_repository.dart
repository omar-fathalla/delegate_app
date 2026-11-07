import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/attendance/domain/entities/attendance.dart';
import 'package:delegate_app/features/attendance/domain/entities/attendance_pagination_result.dart';

abstract class AttendanceRepository {
  Future<Either<Failure, Attendance>> checkIn(
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
  });
  Future<Either<Failure, Attendance>> checkOut(
    String attendanceId,
    double lat,
    double long, {
    required String userId,
    required String organizationId,
  });
  Future<Either<Failure, List<Attendance>>> getHistory(
    String userId,
    String organizationId, {
    String? nationalityID,
    String? phoneNumber,
  });
  Future<Either<Failure, AttendancePaginationResult>> getHistoryPaginated(
    String userId,
    String organizationId, {
    String? nationalityID,
    String? phoneNumber,
    int limit = 20,
    dynamic lastDoc,
  });

  /// All sessions whose check-in falls in [month], across all organizations.
  Future<Either<Failure, List<Attendance>>> getHistoryForMonth(
    String userId, {
    required DateTime month,
    String? nationalityID,
    String? phoneNumber,
  });

  /// Finds the active attendance session (no checkOutTime) for the delegate.
  Future<Either<Failure, Attendance?>> findActiveAttendance(
    String userId,
    String organizationId,
  );

  /// Synchronizes offline attendance records with the remote server.
  Future<Either<Failure, void>> syncPendingAttendance();

  /// Saves or updates a branch with its geofence data.
  Future<Either<Failure, void>> saveBranch({
    required String branchName,
    required double latitude,
    required double longitude,
    required double geofenceRadius,
  });
}
