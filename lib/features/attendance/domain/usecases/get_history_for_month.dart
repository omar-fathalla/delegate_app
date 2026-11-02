import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/attendance/domain/entities/attendance.dart';
import 'package:delegate_app/features/attendance/domain/repositories/attendance_repository.dart';

/// Loads every attendance session of one calendar month (all organizations),
/// independent of the paginated history list.
class GetHistoryForMonth
    implements UseCase<List<Attendance>, GetHistoryForMonthParams> {
  final AttendanceRepository repository;

  GetHistoryForMonth(this.repository);

  @override
  Future<Either<Failure, List<Attendance>>> call(
    GetHistoryForMonthParams params,
  ) {
    return repository.getHistoryForMonth(
      params.userId,
      month: params.month,
      nationalityID: params.nationalityID,
      phoneNumber: params.phoneNumber,
    );
  }
}

class GetHistoryForMonthParams extends Equatable {
  final String userId;
  final DateTime month;
  final String? nationalityID;
  final String? phoneNumber;

  const GetHistoryForMonthParams({
    required this.userId,
    required this.month,
    this.nationalityID,
    this.phoneNumber,
  });

  @override
  List<Object?> get props => [userId, month, nationalityID, phoneNumber];
}
