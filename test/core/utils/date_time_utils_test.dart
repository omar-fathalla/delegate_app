import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/utils/date_time_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DateTimeUtils.parseDate', () {
    test('parses Firestore Timestamp correctly', () {
      final expected = DateTime(2024, 6, 15, 10, 30);
      final timestamp = Timestamp.fromDate(expected);

      final result = DateTimeUtils.parseDate(timestamp);

      expect(result.year, 2024);
      expect(result.month, 6);
      expect(result.day, 15);
    });

    test('parses ISO 8601 String correctly', () {
      const dateString = '2024-01-20T08:00:00.000';

      final result = DateTimeUtils.parseDate(dateString);

      expect(result.year, 2024);
      expect(result.month, 1);
      expect(result.day, 20);
    });

    test('returns DateTime.now() for null input (within 1 second)', () {
      final before = DateTime.now();
      final result = DateTimeUtils.parseDate(null);
      final after = DateTime.now();

      expect(result.isAfter(before) || result.isAtSameMomentAs(before), isTrue);
      expect(result.isBefore(after) || result.isAtSameMomentAs(after), isTrue);
    });

    test('returns DateTime.now() for unsupported type (within 1 second)', () {
      final before = DateTime.now();
      final result = DateTimeUtils.parseDate(42);
      final after = DateTime.now();

      expect(result.isAfter(before) || result.isAtSameMomentAs(before), isTrue);
      expect(result.isBefore(after) || result.isAtSameMomentAs(after), isTrue);
    });
  });

  group('DateTimeUtils.parseNullableDate', () {
    test('returns null for null input', () {
      expect(DateTimeUtils.parseNullableDate(null), isNull);
    });

    test('parses Timestamp correctly', () {
      final expected = DateTime(2023, 3, 10);
      final timestamp = Timestamp.fromDate(expected);

      final result = DateTimeUtils.parseNullableDate(timestamp);

      expect(result, isNotNull);
      expect(result!.year, 2023);
      expect(result.month, 3);
      expect(result.day, 10);
    });

    test('parses String correctly', () {
      const dateString = '2023-12-25';

      final result = DateTimeUtils.parseNullableDate(dateString);

      expect(result, isNotNull);
      expect(result!.month, 12);
      expect(result.day, 25);
    });

    test('returns null for unsupported type', () {
      final result = DateTimeUtils.parseNullableDate(12345);
      expect(result, isNull);
    });
  });
}
