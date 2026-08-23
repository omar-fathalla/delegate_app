import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/notifications/domain/repositories/notification_repository.dart';
import 'package:equatable/equatable.dart';

class DeleteNotificationForUser
    implements UseCase<void, DeleteNotificationForUserParams> {
  final NotificationRepository repository;

  DeleteNotificationForUser(this.repository);

  @override
  Future<Either<Failure, void>> call(DeleteNotificationForUserParams params) {
    return repository.deleteNotificationForUser(
      params.notificationId,
      params.userUid,
    );
  }
}

class DeleteNotificationForUserParams extends Equatable {
  final String notificationId;
  final String userUid;

  const DeleteNotificationForUserParams({
    required this.notificationId,
    required this.userUid,
  });

  @override
  List<Object?> get props => [notificationId, userUid];
}
