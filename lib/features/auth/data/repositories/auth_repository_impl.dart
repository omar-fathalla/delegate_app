import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/services/firestore_session_subscriptions.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:delegate_app/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:delegate_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:delegate_app/features/profile/data/models/delegate_model.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

class AuthRepositoryImpl implements AuthRepository {
  final AuthRemoteDataSource remoteDataSource;
  final AuthLocalDataSource localDataSource;

  /// Best-effort FCM token and topic cleanup. Must not throw.
  final Future<void> Function(String userId)? clearPushRegistration;

  /// TAS-76: asks for the Firestore disk cache to be dropped before the next
  /// session (FirestoreCacheReset.markPending). Must not throw.
  final Future<void> Function()? markFirestoreCacheReset;

  /// TAS-240: drops the cache now if it was marked
  /// (FirestoreCacheReset.runIfPending). Must not throw.
  final Future<void> Function()? runFirestoreCacheReset;

  AuthRepositoryImpl({
    required this.remoteDataSource,
    required this.localDataSource,
    this.clearPushRegistration,
    this.markFirestoreCacheReset,
    this.runFirestoreCacheReset,
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
  Future<Either<Failure, void>> logout({String? userId}) async {
    final uid = userId?.trim() ?? '';
    // TAS-241: mark first. Offline, the push cleanup and sign-out below can
    // take ~17s; if the app is closed before a later mark, the old user's
    // cache stayed for good. clearCachedData keeps this key.
    final markReset = markFirestoreCacheReset;
    if (markReset != null) {
      try {
        await markReset();
      } catch (_) {}
    }
    try {
      await FirestoreSessionSubscriptions.instance.cancelAll();
    } catch (_) {}
    final cleanup = clearPushRegistration;
    // Delete fcm_tokens/{uid} while still signed in. The rules require
    // signedIn(), so a parallel/post sign-out delete is PERMISSION_DENIED
    // and leaves a stale token (M31 3ff8e5d logout).
    if (uid.isNotEmpty && cleanup != null) {
      try {
        await cleanup(uid).timeout(const Duration(seconds: 15));
      } catch (_) {}
    }
    try {
      await remoteDataSource.signOut().timeout(const Duration(seconds: 2));
    } catch (_) {
      // Offline sign-out must not keep the session.
    }
    try {
      await localDataSource.clearCachedData();
    } catch (_) {}
    // TAS-240: the login screen is already up (AuthBloc emits before this
    // runs), so its own runIfPending saw no mark. Drop the cache here, after
    // sign-out, with the session's listeners gone. Unsent writes keep the
    // mark for the next start (FirestoreCacheReset waits for them).
    final runReset = runFirestoreCacheReset;
    if (runReset != null) {
      try {
        await runReset();
      } catch (_) {}
    }
    return const Right(null);
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
