import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:delegate_app/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:delegate_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:delegate_app/features/profile/data/models/delegate_model.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

class AuthRepositoryImpl implements AuthRepository {
  final AuthRemoteDataSource remoteDataSource;
  final AuthLocalDataSource localDataSource;

  AuthRepositoryImpl({
    required this.remoteDataSource,
    required this.localDataSource,
  });

  @override
  Future<Either<Failure, Delegate>> getDelegateByPhone(
    String phoneNumber,
  ) async {
    try {
      final delegate = await remoteDataSource.getDelegateByPhone(phoneNumber);
      if (delegate == null) {
        return const Left(AuthFailure('رقم الهاتف غير مسجل'));
      }
      return Right(delegate);
    } on Failure catch (failure) {
      return Left(failure);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> cacheDelegate(Delegate delegate) async {
    try {
      final model = delegate as DelegateModel;
      await localDataSource.cacheDelegateData(model);
      return const Right(null);
    } on Failure catch (failure) {
      return Left(failure);
    } catch (e) {
      return Left(CacheFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Delegate?>> getCachedDelegate() async {
    try {
      final delegate = localDataSource.getCachedDelegateData();
      return Right(delegate);
    } on Failure catch (failure) {
      return Left(failure);
    } catch (e) {
      return Left(CacheFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> clearCache() async {
    try {
      await localDataSource.clearCachedData();
      return const Right(null);
    } on Failure catch (failure) {
      return Left(failure);
    } catch (e) {
      return Left(CacheFailure(e.toString()));
    }
  }
}
