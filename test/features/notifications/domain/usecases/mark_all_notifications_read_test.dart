import 'package:dartz/dartz.dart';
import 'package:delegate_app/features/notifications/domain/repositories/notification_repository.dart';
import 'package:delegate_app/features/notifications/domain/usecases/mark_all_notifications_read.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockNotificationRepository extends Mock implements NotificationRepository {}

void main() {
  late MarkAllNotificationsRead usecase;
  late MockNotificationRepository mockRepository;

  setUp(() {
    mockRepository = MockNotificationRepository();
    usecase = MarkAllNotificationsRead(mockRepository);
  });

  test('should mark all notifications as read in the repository', () async {
    // Arrange
    when(() => mockRepository.markAllAsRead(any(), any()))
        .thenAnswer((_) async => const Right(null));

    // Act
    final result = await usecase(
      const MarkAllNotificationsReadParams(delegateUid: 'del1', organizationId: 'org1'),
    );

    // Assert
    expect(result, equals(const Right(null)));
    verify(() => mockRepository.markAllAsRead('del1', 'org1')).called(1);
    verifyNoMoreInteractions(mockRepository);
  });
}
