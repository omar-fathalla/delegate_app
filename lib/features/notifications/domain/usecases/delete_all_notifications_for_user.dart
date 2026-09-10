import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/notifications/domain/repositories/notification_repository.dart';
import 'package:equatable/equatable.dart';

class DeleteAllNotificationsForUser
    implements UseCase<void, DeleteAllNotificationsForUserParams> {
  final NotificationRepository repository;

  DeleteAllNotificationsForUser(this.repository);

  @override
  Future<Either<Failure, void>> call(DeleteAllNotificationsForUserParams params) {
    return repository.deleteAllNotificationsForUser(
      notificationIds: params.notificationIds,
      userUid: params.userUid,
      phoneNumber: params.phoneNumber,
    );
  }
}

class DeleteAllNotificationsForUserParams extends Equatable {
  final List<String> notificationIds;
  final String userUid;
  final String? phoneNumber;

  const DeleteAllNotificationsForUserParams({
    required this.notificationIds,
    required this.userUid,
    this.phoneNumber,
  });

  @override
  List<Object?> get props => [notificationIds, userUid, phoneNumber];
}
