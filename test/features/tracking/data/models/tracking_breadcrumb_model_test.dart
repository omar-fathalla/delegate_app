import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:delegate_app/features/tracking/domain/entities/tracking_breadcrumb.dart';
import 'package:delegate_app/features/tracking/data/models/tracking_breadcrumb_model.dart';

void main() {
  group('TrackingBreadcrumbModel', () {
    final now = DateTime(2026, 9, 30, 14, 25);

    final testModel = TrackingBreadcrumbModel(
      id: 'crumb_1',
      latitude: 30.0444,
      longitude: 31.2357,
      timestamp: now,
      speed: 18.5,
      batteryLevel: 75,
      distanceMeters: 42.0,
      isInside: true,
    );

    test('should be a subclass of TrackingBreadcrumb entity', () {
      expect(testModel, isA<TrackingBreadcrumb>());
    });

    test('should correctly serialize toJson and parse fromJson', () {
      final json = testModel.toJson();
      expect(json['id'], 'crumb_1');
      expect(json['latitude'], 30.0444);
      expect(json['longitude'], 31.2357);
      expect(json['timestamp'], isA<Timestamp>());
      expect(json['speed'], 18.5);
      expect(json['batteryLevel'], 75);
      expect(json['distanceMeters'], 42.0);
      expect(json['isInside'], true);

      final fromJson = TrackingBreadcrumbModel.fromJson(json, 'crumb_1');
      expect(fromJson.id, 'crumb_1');
      expect(fromJson.latitude, 30.0444);
      expect(fromJson.longitude, 31.2357);
      expect(fromJson.speed, 18.5);
      expect(fromJson.batteryLevel, 75);
      expect(fromJson.distanceMeters, 42.0);
      expect(fromJson.isInside, true);
    });

    test('should handle null battery and default values gracefully', () {
      final minimalJson = {
        'latitude': 30.0,
        'longitude': 31.0,
        'timestamp': Timestamp.fromDate(now),
      };

      final model = TrackingBreadcrumbModel.fromJson(minimalJson, 'crumb_2');
      expect(model.id, 'crumb_2');
      expect(model.batteryLevel, isNull);
      expect(model.speed, 0.0);
      expect(model.distanceMeters, 0.0);
      expect(model.isInside, true);
    });
  });
}
