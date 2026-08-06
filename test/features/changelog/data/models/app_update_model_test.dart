import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/features/changelog/data/models/app_update_model.dart';
import 'package:delegate_app/features/changelog/domain/entities/app_update.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final tDate = DateTime(2023, 1, 1);
  final tAppUpdateModel = AppUpdateModel(
    id: 'test_id',
    title: 'Update 1',
    titleEn: 'Update 1 EN',
    description: 'Desc',
    descriptionEn: 'Desc EN',
    version: '1.0.0',
    type: UpdateType.feature,
    priority: UpdatePriority.important,
    createdAt: tDate,
    isActive: true,
    highlights: const ['H1'],
    highlightsEn: const ['H1 EN'],
  );

  test('should be a subclass of AppUpdate entity', () {
    expect(tAppUpdateModel, isA<AppUpdate>());
  });

  group('fromJson', () {
    test('should return a valid model when creating from JSON', () {
      final Map<String, dynamic> jsonMap = {
        'title': 'Update 1',
        'titleEn': 'Update 1 EN',
        'description': 'Desc',
        'descriptionEn': 'Desc EN',
        'version': '1.0.0',
        'type': 'feature',
        'priority': 'important',
        'createdAt': Timestamp.fromDate(tDate),
        'isActive': true,
        'highlights': ['H1'],
        'highlightsEn': ['H1 EN'],
      };

      final result = AppUpdateModel.fromJson(jsonMap, 'test_id');

      expect(result.id, equals(tAppUpdateModel.id));
      expect(result.title, equals(tAppUpdateModel.title));
      expect(result.version, equals(tAppUpdateModel.version));
      expect(result.type, equals(tAppUpdateModel.type));
      expect(result.priority, equals(tAppUpdateModel.priority));
      expect(result.createdAt, equals(tAppUpdateModel.createdAt));
      expect(result.isActive, equals(tAppUpdateModel.isActive));
      expect(result.highlights, equals(tAppUpdateModel.highlights));
    });

    test('should handle missing fields', () {
      final Map<String, dynamic> jsonMap = {};

      final result = AppUpdateModel.fromJson(jsonMap, 'test_id');

      expect(result.id, equals('test_id'));
      expect(result.title, equals(''));
      expect(result.type, equals(UpdateType.feature)); // Default
      expect(result.priority, equals(UpdatePriority.normal)); // Default
      expect(result.isActive, equals(true)); // Default
      expect(result.highlights, isEmpty);
    });
  });
}
