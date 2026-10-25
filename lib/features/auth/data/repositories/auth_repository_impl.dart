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
  Future<Either<Failure, List<Delegate>>> loginDelegate({
    required String phoneNumber,
    required String nationalId,
  }) async {
    try {
      final delegates = await remoteDataSource.loginDelegate(
        phoneNumber: phoneNumber,
        nationalId: nationalId,
      );
      final validDelegates = delegates
          .where(
            (delegate) =>
                delegate.status != DelegateStatus.suspended &&
                delegate.status != DelegateStatus.rejected,
          )
          .toList();

      if (validDelegates.isEmpty) {
        return const Left(
          DelegateAccountInactiveFailure(
            'تم تجميد هذا الحساب من قبل الإدارة. يرجى التواصل مع مسؤول المنظمة.',
          ),
        );
      }

      return Right(validDelegates);
    } on Failure catch (failure) {
      return Left(failure);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<Delegate>>> getDelegatesByPhone(
    String phoneNumber,
  ) async {
    try {
      final delegates = await remoteDataSource.getDelegatesByPhone(phoneNumber);
      if (delegates.isEmpty) {
        return const Left(AuthFailure('رقم الهاتف غير مسجل في النظام. يرجى مراجعة مشرف شركتك أو الدعم الفني.'));
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
        return const Left(AuthFailure('تم تجميد هذا الحساب من قبل الإدارة. يرجى التواصل مع مسؤول المنظمة.'));
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

  @override
  Future<Either<Failure, bool>> verifyAdminPassword(
    String email,
    String password,
  ) async {
    try {
      final isValid = await remoteDataSource.verifyAdminPassword(
        email,
        password,
      );
      return Right(isValid);
    } on Failure catch (failure) {
      return Left(failure);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, bool>> verifyPhonePassword(
    String phoneNumber,
    String password,
  ) async {
    try {
      final isValid = await remoteDataSource.verifyPhonePassword(
        phoneNumber,
        password,
      );
      return Right(isValid);
    } on Failure catch (failure) {
      return Left(failure);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }
}
