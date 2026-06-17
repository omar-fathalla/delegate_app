import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/marketing/domain/repositories/marketing_repository.dart';

class GetMarketingCompanies
    implements UseCase<List<Map<String, dynamic>>, String> {
  final MarketingRepository repository;

  GetMarketingCompanies(this.repository);

  @override
  Future<Either<Failure, List<Map<String, dynamic>>>> call(
    String organizationUID,
  ) {
    return repository.getCompanies(organizationUID);
  }
}
