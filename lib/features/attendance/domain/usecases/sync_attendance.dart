import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/attendance/domain/repositories/attendance_repository.dart';
import 'package:equatable/equatable.dart';

/// Sends the attendance a delegate saved on the phone without network
/// (TAS-363).
class SyncAttendance implements UseCase<void, SyncAttendanceParams> {
  final AttendanceRepository repository;

  SyncAttendance(this.repository);

  @override
  Future<Either<Failure, void>> call(SyncAttendanceParams params) async {
    return await repository.syncPendingAttendance(userId: params.userId);
  }
}

class SyncAttendanceParams extends Equatable {
  const SyncAttendanceParams({required this.userId});

  final String userId;

  @override
  List<Object?> get props => [userId];
}
