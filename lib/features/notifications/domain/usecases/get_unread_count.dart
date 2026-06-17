import 'package:delegate_app/features/notifications/domain/repositories/notification_repository.dart';
import 'package:equatable/equatable.dart';

class GetUnreadCount {
  final NotificationRepository repository;

  GetUnreadCount(this.repository);

  Stream<int> call(GetUnreadCountParams params) {
    return repository.getUnreadCount(params.delegateUid, params.organizationId);
  }
}

class GetUnreadCountParams extends Equatable {
  final String delegateUid;
  final String organizationId;

  const GetUnreadCountParams({
    required this.delegateUid,
    required this.organizationId,
  });

  @override
  List<Object?> get props => [delegateUid, organizationId];
}
