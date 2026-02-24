import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/attendance/domain/entities/attendance.dart';
import 'package:delegate_app/features/attendance/domain/repositories/attendance_repository.dart';

class CheckOut implements UseCase<Attendance, CheckOutParams> {
  final AttendanceRepository repository;

  CheckOut(this.repository);

  @override
  Future<Either<Failure, Attendance>> call(CheckOutParams params) async {
    return await repository.checkOut(
      params.attendanceId,
      params.lat,
      params.long,
      userId: params.userId,
    );
  }
}

class CheckOutParams extends Equatable {
  final String attendanceId;
  final String userId;
  final double lat;
  final double long;

  const CheckOutParams({
    required this.attendanceId,
    required this.userId,
    required this.lat,
    required this.long,
  });

  @override
  List<Object> get props => [attendanceId, userId, lat, long];
}
