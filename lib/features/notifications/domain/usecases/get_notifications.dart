import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/notifications/domain/entities/notification_entity.dart';
import 'package:delegate_app/features/notifications/domain/repositories/notification_repository.dart';
import 'package:equatable/equatable.dart';

class GetNotifications
    implements UseCase<List<NotificationEntity>, GetNotificationsParams> {
  final NotificationRepository repository;

  GetNotifications(this.repository);

  @override
  Future<Either<Failure, List<NotificationEntity>>> call(
    GetNotificationsParams params,
  ) {
    return repository.getNotifications(
      params.delegateUid,
      params.organizationId,
    );
  }
}

class GetNotificationsParams extends Equatable {
  final String delegateUid;
  final String organizationId;

  const GetNotificationsParams({
    required this.delegateUid,
    required this.organizationId,
  });

  @override
  List<Object?> get props => [delegateUid, organizationId];
}
