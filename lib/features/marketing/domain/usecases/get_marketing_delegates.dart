import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/marketing/domain/repositories/marketing_repository.dart';

class GetMarketingDelegatesParams {
  final String organizationUID;
  final String? companyUID;

  const GetMarketingDelegatesParams({
    required this.organizationUID,
    this.companyUID,
  });
}

class GetMarketingDelegates
    implements UseCase<List<Delegate>, GetMarketingDelegatesParams> {
  final MarketingRepository repository;

  GetMarketingDelegates(this.repository);

  @override
  Future<Either<Failure, List<Delegate>>> call(
    GetMarketingDelegatesParams params,
  ) {
    return repository.getDelegates(params.organizationUID, params.companyUID);
  }
}
