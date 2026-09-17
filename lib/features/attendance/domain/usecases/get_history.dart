import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/attendance/domain/entities/attendance.dart';
import 'package:delegate_app/features/attendance/domain/repositories/attendance_repository.dart';

class GetHistory implements UseCase<List<Attendance>, GetHistoryParams> {
  final AttendanceRepository repository;

  GetHistory(this.repository);

  @override
  Future<Either<Failure, List<Attendance>>> call(
    GetHistoryParams params,
  ) async {
    return await repository.getHistory(
      params.userId,
      params.organizationId,
      nationalityID: params.nationalityID,
      phoneNumber: params.phoneNumber,
    );
  }
}

class GetHistoryParams extends Equatable {
  final String userId;
  final String organizationId;
  final String? nationalityID;
  final String? phoneNumber;

  const GetHistoryParams({
    required this.userId,
    required this.organizationId,
    this.nationalityID,
    this.phoneNumber,
  });

  @override
  List<Object?> get props => [
        userId,
        organizationId,
        nationalityID,
        phoneNumber,
      ];
}
