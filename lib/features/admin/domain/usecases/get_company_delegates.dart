import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/admin/domain/repositories/admin_repository.dart';
import 'package:equatable/equatable.dart';

class GetCompanyDelegates
    implements UseCase<CompanyDelegatesResult, GetCompanyDelegatesParams> {
  final AdminRepository repository;

  GetCompanyDelegates(this.repository);

  @override
  Future<Either<Failure, CompanyDelegatesResult>> call(
    GetCompanyDelegatesParams params,
  ) async {
    return await repository.getCompanyDelegates(
      params.organizationUID,
      params.companyUID,
    );
  }
}

class GetCompanyDelegatesParams extends Equatable {
  final String organizationUID;
  final String companyUID;

  const GetCompanyDelegatesParams({
    required this.organizationUID,
    required this.companyUID,
  });

  @override
  List<Object> get props => [organizationUID, companyUID];
}
