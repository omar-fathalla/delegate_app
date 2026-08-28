import 'package:delegate_app/features/notifications/domain/entities/notification_entity.dart';
import 'package:delegate_app/features/notifications/domain/repositories/notification_repository.dart';

class GetCachedNotifications {
  final NotificationRepository repository;

  GetCachedNotifications(this.repository);

  Future<List<NotificationEntity>> call(String delegateUid) async {
    return repository.getCachedNotifications(delegateUid);
  }
}
