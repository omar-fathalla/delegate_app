import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/notifications/data/datasources/notification_local_data_source.dart';
import 'package:delegate_app/features/notifications/data/datasources/notification_remote_data_source.dart';
import 'package:delegate_app/features/notifications/domain/entities/notification_entity.dart';
import 'package:delegate_app/features/notifications/domain/repositories/notification_repository.dart';

class NotificationRepositoryImpl implements NotificationRepository {
  final NotificationRemoteDataSource remoteDataSource;
  final NotificationLocalDataSource? localDataSource;

  NotificationRepositoryImpl({
    required this.remoteDataSource,
    this.localDataSource,
  });

  @override
  Future<List<NotificationEntity>> getCachedNotifications(String delegateUid) async {
    if (localDataSource == null) return [];
    try {
      return await localDataSource!.getCachedNotifications(delegateUid);
    } catch (_) {
      return [];
    }
  }

  @override
  Future<Either<Failure, List<NotificationEntity>>> getNotifications(
    String delegateUid,
    String organizationId, {
    String? phoneNumber,
    String? userRole,
    DateTime? accountCreatedAt,
  }) async {
    try {
      final notifications = await remoteDataSource.getNotifications(
        delegateUid,
        organizationId,
        phoneNumber: phoneNumber,
        userRole: userRole,
        accountCreatedAt: accountCreatedAt,
      );
      if (localDataSource != null) {
        await localDataSource!.cacheNotifications(delegateUid, notifications);
      }
      return Right(notifications);
    } catch (e) {
      if (localDataSource != null) {
        final cached = await localDataSource!.getCachedNotifications(delegateUid);
        if (cached.isNotEmpty) {
          return Right(cached);
        }
      }
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Stream<int> getUnreadCount(
    String delegateUid,
    String organizationId, {
    String? phoneNumber,
    String? userRole,
    DateTime? accountCreatedAt,
  }) {
    return remoteDataSource.getUnreadCount(
      delegateUid,
      organizationId,
      phoneNumber: phoneNumber,
      userRole: userRole,
      accountCreatedAt: accountCreatedAt,
    );
  }

  @override
  Future<Either<Failure, void>> markAsRead(String notificationId) async {
    try {
      await remoteDataSource.markAsRead(notificationId);
      return const Right(null);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> markAllAsRead(
    String delegateUid,
    String organizationId,
  ) async {
    try {
      if (localDataSource != null) {
        await localDataSource!.markAllAsReadInCache(delegateUid);
      }
      await remoteDataSource.markAllAsRead(delegateUid, organizationId);
      return const Right(null);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> deleteNotificationForUser(
    String notificationId,
    String userUid,
  ) async {
    try {
      if (localDataSource != null) {
        await localDataSource!.deleteNotificationInCache(userUid, notificationId);
      }
      await remoteDataSource.deleteNotificationForUser(notificationId, userUid);
      return const Right(null);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> deleteAllNotificationsForUser({
    required List<String> notificationIds,
    required String userUid,
    String? phoneNumber,
  }) async {
    try {
      if (localDataSource != null) {
        await localDataSource!.clearAllNotificationsInCache(userUid);
      }
      await remoteDataSource.deleteAllNotificationsForUser(
        notificationIds,
        userUid,
        phoneNumber: phoneNumber,
      );
      return const Right(null);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }
}
