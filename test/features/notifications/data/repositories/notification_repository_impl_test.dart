import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/notifications/data/datasources/notification_remote_data_source.dart';
import 'package:delegate_app/features/notifications/data/models/notification_model.dart';
import 'package:delegate_app/features/notifications/data/repositories/notification_repository_impl.dart';
import 'package:delegate_app/features/notifications/domain/entities/notification_entity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockNotificationRemoteDataSource extends Mock implements NotificationRemoteDataSource {}

void main() {
  late NotificationRepositoryImpl repository;
  late MockNotificationRemoteDataSource mockRemoteDataSource;

  setUp(() {
    mockRemoteDataSource = MockNotificationRemoteDataSource();
    repository = NotificationRepositoryImpl(remoteDataSource: mockRemoteDataSource);
  });

  final tNotificationModel = NotificationModel(
    id: 'notification123',
    delegateUid: 'delegate123',
    organizationId: 'org123',
    companyId: 'company123',
    title: 'Test Notification',
    body: 'Notification body',
    type: 'general',
    taskId: 'task123',
    isRead: false,
    createdAt: DateTime(2023, 1, 1),
  );

  group('getNotifications', () {
    test('should return list of NotificationEntity on success', () async {
      when(() => mockRemoteDataSource.getNotifications(any(), any()))
          .thenAnswer((_) async => [tNotificationModel]);

      final result = await repository.getNotifications('delegate123', 'org123');

      result.fold(
        (l) => fail('Should be Right'),
        (r) => expect(r, equals([tNotificationModel])),
      );
    });

    test('should return ServerFailure on ServerException', () async {
      when(() => mockRemoteDataSource.getNotifications(any(), any()))
          .thenThrow(Exception('Failed to get notifications'));

      final result = await repository.getNotifications('delegate123', 'org123');

      expect(result, isA<Left<Failure, List<NotificationEntity>>>());
    });
  });

  group('getUnreadCount', () {
    test('should return stream of int', () {
      when(() => mockRemoteDataSource.getUnreadCount(any(), any()))
          .thenAnswer((_) => Stream.value(2));

      final result = repository.getUnreadCount('delegate123', 'org123');

      expect(result, emits(2));
    });
  });

  group('markAsRead', () {
    test('should return void on success', () async {
      when(() => mockRemoteDataSource.markAsRead(any()))
          .thenAnswer((_) async => {});

      final result = await repository.markAsRead('notif123');

      expect(result, equals(const Right(null)));
    });

    test('should return ServerFailure on exception', () async {
      when(() => mockRemoteDataSource.markAsRead(any()))
          .thenThrow(Exception());

      final result = await repository.markAsRead('notif123');

      expect(result, isA<Left<Failure, void>>());
    });
  });

  group('markAllAsRead', () {
    test('should return void on success', () async {
      when(() => mockRemoteDataSource.markAllAsRead(any(), any()))
          .thenAnswer((_) async => {});

      final result = await repository.markAllAsRead('delegate123', 'org123');

      expect(result, equals(const Right(null)));
    });

    test('should return ServerFailure on exception', () async {
      when(() => mockRemoteDataSource.markAllAsRead(any(), any()))
          .thenThrow(Exception());

      final result = await repository.markAllAsRead('delegate123', 'org123');

      expect(result, isA<Left<Failure, void>>());
    });
  });
}
