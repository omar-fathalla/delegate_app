import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/features/attendance/data/models/attendance_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const tId = '1';
  const tUserId = 'user123';
  final tCheckInDateTime = DateTime(2023, 1, 1, 8, 0);
  final tCheckOutDateTime = DateTime(2023, 1, 1, 17, 0);
  final tCheckInTimestamp = Timestamp.fromDate(tCheckInDateTime);
  final tCheckOutTimestamp = Timestamp.fromDate(tCheckOutDateTime);

  group('AttendanceModel.fromJson', () {
    test('should return a valid model from JSON with Timestamps', () {
      // arrange
      final Map<String, dynamic> json = {
        'userId': tUserId,
        'checkInTime': tCheckInTimestamp,
        'checkOutTime': tCheckOutTimestamp,
        'latitude': 12.34,
        'longitude': 56.78,
        'imageUrl': 'http://example.com/image.jpg',
        'branchName': 'Main Branch',
      };
      // act
      final result = AttendanceModel.fromJson(json, tId);
      // assert
      expect(result.id, tId);
      expect(result.userId, tUserId);
      expect(result.checkInTime, tCheckInDateTime);
      expect(result.checkOutTime, tCheckOutDateTime);
      expect(result.latitude, 12.34);
      expect(result.longitude, 56.78);
      expect(result.imageUrl, 'http://example.com/image.jpg');
      expect(result.branchName, 'Main Branch');
    });

    test('should return a valid model from JSON with ISO 8601 strings', () {
      // arrange
      final Map<String, dynamic> json = {
        'userId': tUserId,
        'checkInTime': tCheckInDateTime.toIso8601String(),
        'checkOutTime': tCheckOutDateTime.toIso8601String(),
        'latitude': 12.34,
        'longitude': 56.78,
        'imageUrl': 'http://example.com/image.jpg',
        'branchName': 'Main Branch',
      };
      // act
      final result = AttendanceModel.fromJson(json, tId);
      // assert
      expect(result.id, tId);
      expect(result.userId, tUserId);
      expect(result.checkInTime, tCheckInDateTime);
      expect(result.checkOutTime, tCheckOutDateTime);
    });

    test('should return a model with null optional fields', () {
      // arrange
      final Map<String, dynamic> json = {
        'userId': tUserId,
        'checkInTime': tCheckInTimestamp,
        'checkOutTime': null,
        'latitude': null,
        'longitude': null,
        'imageUrl': null,
        'branchName': null,
      };
      // act
      final result = AttendanceModel.fromJson(json, tId);
      // assert
      expect(result.id, tId);
      expect(result.userId, tUserId);
      expect(result.checkInTime, tCheckInDateTime);
      expect(result.checkOutTime, isNull);
      expect(result.latitude, isNull);
      expect(result.longitude, isNull);
      expect(result.imageUrl, isNull);
      expect(result.branchName, isNull);
    });

    test('should return empty string for userId if missing', () {
      // arrange
      final Map<String, dynamic> json = {'checkInTime': tCheckInTimestamp};
      // act
      final result = AttendanceModel.fromJson(json, tId);
      // assert
      expect(result.userId, '');
    });

    test('should fallback to now() for invalid checkInTime type', () {
      // arrange
      final Map<String, dynamic> json = {
        'userId': tUserId,
        'checkInTime': 123, // Invalid type
      };

      final now = DateTime.now();
      // act
      final result = AttendanceModel.fromJson(json, tId);

      // assert
      // It should be very close to 'now'
      expect(result.checkInTime.difference(now).inSeconds.abs(), lessThan(5));
    });

    test('should handle integer values for latitude and longitude', () {
      // arrange
      final Map<String, dynamic> json = {
        'userId': tUserId,
        'checkInTime': tCheckInTimestamp,
        'latitude': 12,
        'longitude': 56,
      };
      // act
      final result = AttendanceModel.fromJson(json, tId);
      // assert
      expect(result.latitude, 12.0);
      expect(result.longitude, 56.0);
    });
  });
}
