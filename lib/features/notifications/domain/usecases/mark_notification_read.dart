import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/notifications/domain/repositories/notification_repository.dart';
import 'package:equatable/equatable.dart';

class MarkNotificationRead
    implements UseCase<void, MarkNotificationReadParams> {
  final NotificationRepository repository;

  MarkNotificationRead(this.repository);

  @override
  Future<Either<Failure, void>> call(MarkNotificationReadParams params) {
    return repository.markAsRead(params.notificationId);
  }
}

class MarkNotificationReadParams extends Equatable {
  final String notificationId;

  const MarkNotificationReadParams({required this.notificationId});

  @override
  List<Object?> get props => [notificationId];
}
