import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/features/feedback/data/models/feedback_model.dart';
import 'package:delegate_app/features/feedback/domain/entities/feedback_entity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final tDate = DateTime(2023, 1, 1);
  final tFeedbackModel = FeedbackModel(
    id: 'test_id',
    userId: 'user_123',
    userName: 'Test User',
    userEmail: 'test@example.com',
    type: FeedbackType.featureRequest,
    content: 'Please add a dark mode feature',
    screenshotUrl: 'http://example.com/screenshot.png',
    status: FeedbackStatus.pending,
    createdAt: tDate,
    updatedAt: tDate,
    adminResponse: 'We will look into it',
  );

  test('should be a subclass of FeedbackEntity', () async {
    // Assert
    expect(tFeedbackModel, isA<FeedbackEntity>());
  });

  group('fromJson', () {
    test('should return a valid model when creating from JSON', () async {
      // Arrange
      final Map<String, dynamic> jsonMap = {
        'userId': 'user_123',
        'userName': 'Test User',
        'userEmail': 'test@example.com',
        'type': 'feature_request',
        'content': 'Please add a dark mode feature',
        'screenshotUrl': 'http://example.com/screenshot.png',
        'status': 'pending',
        'createdAt': Timestamp.fromDate(tDate),
        'updatedAt': Timestamp.fromDate(tDate),
        'adminResponse': 'We will look into it',
      };

      // Act
      final result = FeedbackModel.fromJson(jsonMap, 'test_id');

      // Assert
      expect(result, equals(tFeedbackModel));
    });
  });

  group('toJson', () {
    test('should return a JSON map containing the proper data', () async {
      // Act
      final result = tFeedbackModel.toJson();

      // Assert
      final expectedMap = {
        'userId': 'user_123',
        'userName': 'Test User',
        'userEmail': 'test@example.com',
        'type': 'feature_request',
        'content': 'Please add a dark mode feature',
        'screenshotUrl': 'http://example.com/screenshot.png',
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': Timestamp.fromDate(tDate),
        'adminResponse': 'We will look into it',
      };
      
      // We cannot directly compare FieldValue.serverTimestamp() in expectedMap, 
      // so we compare other fields.
      expect(result['userId'], equals(expectedMap['userId']));
      expect(result['userName'], equals(expectedMap['userName']));
      expect(result['type'], equals(expectedMap['type']));
      expect(result['content'], equals(expectedMap['content']));
      expect(result['status'], equals(expectedMap['status']));
      expect(result['updatedAt'], equals(expectedMap['updatedAt']));
    });
  });
}
