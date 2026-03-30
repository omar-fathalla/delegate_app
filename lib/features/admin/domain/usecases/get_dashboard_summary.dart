import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/admin/domain/entities/dashboard_summary.dart';
import 'package:delegate_app/features/admin/domain/repositories/admin_repository.dart';
import 'package:equatable/equatable.dart';

class GetDashboardSummary {
  final AdminRepository repository;

  GetDashboardSummary(this.repository);

  Future<Either<Failure, DashboardSummary>> call(
    GetDashboardSummaryParams params,
  ) {
    return repository.getDashboardSummary(
      params.organizationUID,
      params.companyUID,
    );
  }
}

class GetDashboardSummaryParams extends Equatable {
  final String organizationUID;
  final String companyUID;

  const GetDashboardSummaryParams({
    required this.organizationUID,
    required this.companyUID,
  });

  @override
  List<Object?> get props => [organizationUID, companyUID];
}
