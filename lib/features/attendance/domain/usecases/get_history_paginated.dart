import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/attendance/domain/entities/attendance_pagination_result.dart';
import 'package:delegate_app/features/attendance/domain/repositories/attendance_repository.dart';
import 'package:equatable/equatable.dart';

class GetHistoryPaginated
    implements UseCase<AttendancePaginationResult, GetHistoryPaginatedParams> {
  final AttendanceRepository repository;

  GetHistoryPaginated(this.repository);

  @override
  Future<Either<Failure, AttendancePaginationResult>> call(
    GetHistoryPaginatedParams params,
  ) async {
    return await repository.getHistoryPaginated(
      params.userId,
      params.organizationId,
      nationalityID: params.nationalityID,
      phoneNumber: params.phoneNumber,
      limit: params.limit,
      lastDoc: params.lastDoc,
    );
  }
}

class GetHistoryPaginatedParams extends Equatable {
  final String userId;
  final String organizationId;
  final String? nationalityID;
  final String? phoneNumber;
  final int limit;
  final dynamic lastDoc;

  const GetHistoryPaginatedParams({
    required this.userId,
    required this.organizationId,
    this.nationalityID,
    this.phoneNumber,
    this.limit = 20,
    this.lastDoc,
  });

  @override
  List<Object?> get props => [
    userId,
    organizationId,
    nationalityID,
    phoneNumber,
    limit,
    lastDoc,
  ];
}
