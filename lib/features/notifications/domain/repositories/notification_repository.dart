import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/notifications/domain/entities/notification_entity.dart';

abstract class NotificationRepository {
  Future<Either<Failure, List<NotificationEntity>>> getNotifications(
    String delegateUid,
    String organizationId,
  );

  Stream<int> getUnreadCount(String delegateUid, String organizationId);

  Future<Either<Failure, void>> markAsRead(String notificationId);

  Future<Either<Failure, void>> markAllAsRead(
    String delegateUid,
    String organizationId,
  );
}
