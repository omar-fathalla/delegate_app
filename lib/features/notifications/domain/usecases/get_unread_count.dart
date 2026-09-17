import 'package:delegate_app/features/notifications/domain/repositories/notification_repository.dart';
import 'package:equatable/equatable.dart';

class GetUnreadCount {
  final NotificationRepository repository;

  GetUnreadCount(this.repository);

  Stream<int> call(GetUnreadCountParams params) {
    return repository.getUnreadCount(
      params.delegateUid,
      params.organizationId,
      phoneNumber: params.phoneNumber,
      userRole: params.userRole,
      accountCreatedAt: params.accountCreatedAt,
    );
  }
}

class GetUnreadCountParams extends Equatable {
  final String delegateUid;
  final String organizationId;
  final String? phoneNumber;
  final String? userRole;
  final DateTime? accountCreatedAt;

  const GetUnreadCountParams({
    required this.delegateUid,
    required this.organizationId,
    this.phoneNumber,
    this.userRole,
    this.accountCreatedAt,
  });

  @override
  List<Object?> get props => [
        delegateUid,
        organizationId,
        phoneNumber,
        userRole,
        accountCreatedAt,
      ];
}
