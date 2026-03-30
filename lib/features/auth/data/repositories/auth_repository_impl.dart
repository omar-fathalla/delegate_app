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
  Future<Either<Failure, List<Delegate>>> getDelegatesByPhone(
    String phoneNumber,
  ) async {
    try {
      // 1. Sign in anonymously FIRST to satisfy Firestore rules (request.auth != null)
      await remoteDataSource.signInAnonymously();

      // 2. Now fetch the delegate data
      final delegates = await remoteDataSource.getDelegatesByPhone(phoneNumber);
      if (delegates.isEmpty) {
        return const Left(AuthFailure('رقم الهاتف غير مسجل'));
      }

      // Filter out suspended/rejected delegates
      final validDelegates = delegates
          .where(
            (delegate) =>
                delegate.status != DelegateStatus.suspended &&
                delegate.status != DelegateStatus.rejected,
          )
          .toList();

      if (validDelegates.isEmpty) {
        // Determine which message to show from the first delegate's status
        final first = delegates.first;
        if (first.status == DelegateStatus.suspended) {
          return const Left(AuthFailure('تم تعليق حسابك. تواصل مع الإدارة.'));
        }
        return const Left(AuthFailure('تم رفض حسابك. تواصل مع الإدارة.'));
      }

      return Right(validDelegates);
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
  Future<Either<Failure, void>> cacheAllDelegates(
    List<Delegate> delegates,
  ) async {
    try {
      final models = delegates.map((d) => d as DelegateModel).toList();
      await localDataSource.cacheAllDelegatesData(models);
      return const Right(null);
    } on Failure catch (failure) {
      return Left(failure);
    } catch (e) {
      return Left(CacheFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<Delegate>>> getCachedAllDelegates() async {
    try {
      final delegates = localDataSource.getCachedAllDelegatesData();
      return Right(delegates);
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
