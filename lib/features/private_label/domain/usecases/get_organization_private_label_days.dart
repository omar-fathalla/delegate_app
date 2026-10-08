import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_day.dart';
import 'package:delegate_app/features/private_label/domain/repositories/private_label_repository.dart';

class GetOrganizationPrivateLabelDaysParams {
  final String organizationUID;
  final String monthKey;
  final String? companyUID;

  const GetOrganizationPrivateLabelDaysParams({
    required this.organizationUID,
    required this.monthKey,
    this.companyUID,
  });
}

class GetOrganizationPrivateLabelDays
    implements UseCase<List<PrivateLabelDay>, GetOrganizationPrivateLabelDaysParams> {
  final PrivateLabelRepository repository;

  GetOrganizationPrivateLabelDays(this.repository);

  @override
  Future<Either<Failure, List<PrivateLabelDay>>> call(
    GetOrganizationPrivateLabelDaysParams params,
  ) {
    return repository.getOrganizationMonthDays(
      organizationUID: params.organizationUID,
      monthKey: params.monthKey,
      companyUID: params.companyUID,
    );
  }
}
