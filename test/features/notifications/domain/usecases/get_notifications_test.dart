import 'package:dartz/dartz.dart';
import 'package:delegate_app/features/notifications/domain/entities/notification_entity.dart';
import 'package:delegate_app/features/notifications/domain/repositories/notification_repository.dart';
import 'package:delegate_app/features/notifications/domain/usecases/get_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockNotificationRepository extends Mock implements NotificationRepository {}

void main() {
  late GetNotifications usecase;
  late MockNotificationRepository mockRepository;

  setUp(() {
    mockRepository = MockNotificationRepository();
    usecase = GetNotifications(mockRepository);
  });

  final tNotificationList = [
    NotificationEntity(
      id: '1',
      delegateUid: 'del1',
      organizationId: 'org1',
      companyId: 'comp1',
      title: 'Title',
      body: 'Body',
      type: 'general',
      isRead: false,
      createdAt: DateTime(2023),
    )
  ];

  test('should get notifications from the repository', () async {
    // Arrange
    when(() => mockRepository.getNotifications(any(), any()))
        .thenAnswer((_) async => Right(tNotificationList));

    // Act
    final result = await usecase(
      const GetNotificationsParams(delegateUid: 'del1', organizationId: 'org1'),
    );

    // Assert
    expect(result, equals(Right(tNotificationList)));
    verify(() => mockRepository.getNotifications('del1', 'org1')).called(1);
    verifyNoMoreInteractions(mockRepository);
  });
}
