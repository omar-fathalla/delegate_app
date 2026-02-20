import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/attendance/domain/repositories/attendance_repository.dart';

class SyncAttendance implements UseCase<void, NoParams> {
  final AttendanceRepository repository;

  SyncAttendance(this.repository);

  @override
  Future<Either<Failure, void>> call(NoParams params) async {
    return await repository.syncPendingAttendance();
  }
}
