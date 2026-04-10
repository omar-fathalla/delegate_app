import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/marketing/data/datasources/marketing_remote_data_source.dart';
import 'package:delegate_app/features/marketing/domain/repositories/marketing_repository.dart';

class MarketingRepositoryImpl implements MarketingRepository {
  final MarketingRemoteDataSource remoteDataSource;

  MarketingRepositoryImpl({required this.remoteDataSource});

  @override
  Future<Either<Failure, List<Map<String, dynamic>>>> getCompanies(String organizationUID) async {
    try {
      final companies = await remoteDataSource.getCompanies(organizationUID);
      return Right(companies);
    } on Failure catch (f) {
      return Left(f);
    } catch (_) {
      return const Left(ServerFailure('حدث خطأ غير متوقع.'));
    }
  }

  @override
  Future<Either<Failure, List<Delegate>>> getDelegates(String organizationUID, String? companyUID) async {
    try {
      final delegates = await remoteDataSource.getDelegates(organizationUID, companyUID);
      return Right(delegates);
    } on Failure catch (f) {
      return Left(f);
    } catch (_) {
      return const Left(ServerFailure('حدث خطأ غير متوقع.'));
    }
  }
}
