import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/features/notifications/data/models/notification_model.dart';
import 'package:delegate_app/features/notifications/domain/entities/notification_entity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockDocumentSnapshot extends Mock implements DocumentSnapshot {}

void main() {
  final tDateTime = DateTime(2023, 1, 1);
  final tTimestamp = Timestamp.fromDate(tDateTime);

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
    createdAt: tDateTime,
  );

  test('should be a subclass of NotificationEntity', () {
    // Assert
    expect(tNotificationModel, isA<NotificationEntity>());
  });

  group('fromFirestore', () {
    test('should return a valid model when creating from DocumentSnapshot', () {
      // Arrange
      final Map<String, dynamic> data = {
        'delegateUid': 'delegate123',
        'organizationId': 'org123',
        'companyId': 'company123',
        'title': 'Test Notification',
        'body': 'Notification body',
        'type': 'general',
        'taskId': 'task123',
        'isRead': false,
        'createdAt': tTimestamp,
      };
      
      final mockDocumentSnapshot = MockDocumentSnapshot();
      when(() => mockDocumentSnapshot.data()).thenReturn(data);
      when(() => mockDocumentSnapshot.id).thenReturn('notification123');

      // Act
      final result = NotificationModel.fromFirestore(mockDocumentSnapshot);

      // Assert
      expect(result, equals(tNotificationModel));
    });
  });

  group('toFirestore', () {
    test('should return a JSON map containing the proper data', () {
      // Act
      final result = tNotificationModel.toFirestore();

      // Assert
      final expectedMap = {
        'delegateUid': 'delegate123',
        'organizationId': 'org123',
        'companyId': 'company123',
        'title': 'Test Notification',
        'body': 'Notification body',
        'type': 'general',
        'taskId': 'task123',
        'penaltyId': null,
        'isRead': false,
        'read': false,
        'createdAt': tTimestamp,
        'deletedBy': const [],
      };
      expect(result, equals(expectedMap));
    });
  });
}
