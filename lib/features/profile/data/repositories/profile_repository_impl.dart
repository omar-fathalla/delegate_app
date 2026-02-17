import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/exceptions.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/profile/data/datasources/profile_remote_data_source.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/profile/domain/repositories/profile_repository.dart';

class ProfileRepositoryImpl implements ProfileRepository {
  final ProfileRemoteDataSource remoteDataSource;

  ProfileRepositoryImpl({required this.remoteDataSource});

  @override
  Future<Either<Failure, Delegate>> getDelegateProfile(String uid) async {
    try {
      final remoteProfile = await remoteDataSource.getDelegateProfile(uid);
      return Right(remoteProfile);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }
}
