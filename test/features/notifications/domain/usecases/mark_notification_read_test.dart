import 'package:dartz/dartz.dart';
import 'package:delegate_app/features/notifications/domain/repositories/notification_repository.dart';
import 'package:delegate_app/features/notifications/domain/usecases/mark_notification_read.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockNotificationRepository extends Mock implements NotificationRepository {}

void main() {
  late MarkNotificationRead usecase;
  late MockNotificationRepository mockRepository;

  setUp(() {
    mockRepository = MockNotificationRepository();
    usecase = MarkNotificationRead(mockRepository);
  });

  test('should mark a notification as read in the repository', () async {
    // Arrange
    when(() => mockRepository.markAsRead(any()))
        .thenAnswer((_) async => const Right(null));

    // Act
    final result = await usecase(
      const MarkNotificationReadParams(notificationId: 'notif1'),
    );

    // Assert
    expect(result, equals(const Right(null)));
    verify(() => mockRepository.markAsRead('notif1')).called(1);
    verifyNoMoreInteractions(mockRepository);
  });
}
