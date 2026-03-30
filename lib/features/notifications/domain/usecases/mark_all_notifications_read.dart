import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/notifications/domain/repositories/notification_repository.dart';
import 'package:equatable/equatable.dart';

class MarkAllNotificationsRead
    implements UseCase<void, MarkAllNotificationsReadParams> {
  final NotificationRepository repository;

  MarkAllNotificationsRead(this.repository);

  @override
  Future<Either<Failure, void>> call(MarkAllNotificationsReadParams params) {
    return repository.markAllAsRead(params.delegateUid, params.organizationId);
  }
}

class MarkAllNotificationsReadParams extends Equatable {
  final String delegateUid;
  final String organizationId;

  const MarkAllNotificationsReadParams({
    required this.delegateUid,
    required this.organizationId,
  });

  @override
  List<Object?> get props => [delegateUid, organizationId];
}
