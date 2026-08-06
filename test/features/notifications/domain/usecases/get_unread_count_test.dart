import 'package:delegate_app/features/notifications/domain/repositories/notification_repository.dart';
import 'package:delegate_app/features/notifications/domain/usecases/get_unread_count.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockNotificationRepository extends Mock implements NotificationRepository {}

void main() {
  late GetUnreadCount usecase;
  late MockNotificationRepository mockRepository;

  setUp(() {
    mockRepository = MockNotificationRepository();
    usecase = GetUnreadCount(mockRepository);
  });

  test('should get unread count stream from the repository', () {
    // Arrange
    when(() => mockRepository.getUnreadCount(any(), any()))
        .thenAnswer((_) => Stream.value(3));

    // Act
    final result = usecase(
      const GetUnreadCountParams(delegateUid: 'del1', organizationId: 'org1'),
    );

    // Assert
    expect(result, emits(3));
    verify(() => mockRepository.getUnreadCount('del1', 'org1')).called(1);
    verifyNoMoreInteractions(mockRepository);
  });
}
