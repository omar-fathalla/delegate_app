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
    senderName: 'محمد أحمد',
    senderRole: 'superAdmin',
  );

  test('should be a subclass of NotificationEntity', () {
    // Assert
    expect(tNotificationModel, isA<NotificationEntity>());
  });

  group('fromFirestore', () {
    test('should return a valid model with sender info and sanitized text', () {
      // Arrange
      final Map<String, dynamic> data = {
        'delegateUid': 'delegate123',
        'organizationId': 'org123',
        'companyId': 'company123',
        'title': '✅ Test Notification',
        'body': '🚨 Notification body',
        'type': 'general',
        'taskId': 'task123',
        'isRead': false,
        'createdAt': tTimestamp,
        'senderName': 'محمد أحمد',
        'senderRole': 'superAdmin',
      };

      final mockDocumentSnapshot = MockDocumentSnapshot();
      when(() => mockDocumentSnapshot.data()).thenReturn(data);
      when(() => mockDocumentSnapshot.id).thenReturn('notification123');

      // Act
      final result = NotificationModel.fromFirestore(mockDocumentSnapshot);

      // Assert
      expect(result.title, 'Test Notification');
      expect(result.body, 'Notification body');
      expect(result.senderName, 'محمد أحمد');
      expect(result.senderRole, 'superAdmin');
      expect(result, equals(tNotificationModel));
    });
  });

  group('toFirestore', () {
    test('should return a JSON map containing the proper data with sender info', () {
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
        'senderName': 'محمد أحمد',
        'senderRole': 'superAdmin',
      };
      expect(result, equals(expectedMap));
    });
  });

  group('role mapping & sanitization', () {
    test('should map English role keys to Arabic correctly', () {
      expect(NotificationModel.formatSenderRoleArabic('superAdmin'), 'سوبر أدمن');
      expect(NotificationModel.formatSenderRoleArabic('super-admin'), 'سوبر أدمن');
      expect(NotificationModel.formatSenderRoleArabic('organizationAdmin'), 'مسؤول المنظمة');
      expect(NotificationModel.formatSenderRoleArabic('branchesMarketingManager'), 'مسؤول تسويق الفروع');
      expect(NotificationModel.formatSenderRoleArabic('marketingPromotion'), 'مسؤول تسويق العروض');
      expect(NotificationModel.formatSenderRoleArabic('marketing_promotion'), 'مسؤول تسويق العروض');
      expect(NotificationModel.formatSenderRoleArabic('technicalSupport'), 'الدعم الفني');
      expect(NotificationModel.formatSenderRoleArabic('technical_support'), 'الدعم الفني');
      expect(NotificationModel.formatSenderRoleArabic('supervisor'), 'مشرف الشركة');
      expect(NotificationModel.formatSenderRoleArabic('delegate'), 'مندوب');
    });

    test('should sanitize emojis completely', () {
      expect(NotificationModel.sanitizeText('✅ اعتماد نهائي للغرامة'), 'اعتماد نهائي للغرامة');
      expect(NotificationModel.sanitizeText('🚨 تسجيل مخالفة جديدة بحقك'), 'تسجيل مخالفة جديدة بحقك');
      expect(NotificationModel.sanitizeText('إيداع رصيد في محفظتك 💰'), 'إيداع رصيد في محفظتك');
    });
  });
}
