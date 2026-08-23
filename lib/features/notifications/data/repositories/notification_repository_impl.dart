import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/notifications/data/datasources/notification_remote_data_source.dart';
import 'package:delegate_app/features/notifications/domain/entities/notification_entity.dart';
import 'package:delegate_app/features/notifications/domain/repositories/notification_repository.dart';

class NotificationRepositoryImpl implements NotificationRepository {
  final NotificationRemoteDataSource remoteDataSource;

  NotificationRepositoryImpl({required this.remoteDataSource});

  @override
  Future<Either<Failure, List<NotificationEntity>>> getNotifications(
    String delegateUid,
    String organizationId, {
    String? phoneNumber,
  }) async {
    try {
      final notifications = await remoteDataSource.getNotifications(
        delegateUid,
        organizationId,
        phoneNumber: phoneNumber,
      );
      return Right(notifications);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Stream<int> getUnreadCount(
    String delegateUid,
    String organizationId, {
    String? phoneNumber,
  }) {
    return remoteDataSource.getUnreadCount(
      delegateUid,
      organizationId,
      phoneNumber: phoneNumber,
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
      await remoteDataSource.deleteNotificationForUser(notificationId, userUid);
      return const Right(null);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }
}
