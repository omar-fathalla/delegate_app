import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

abstract class MarketingRepository {
  Future<Either<Failure, List<Map<String, dynamic>>>> getCompanies(String organizationUID);
  Future<Either<Failure, List<Delegate>>> getDelegates(String organizationUID, String? companyUID);
}
