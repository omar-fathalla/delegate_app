import 'package:cloud_firestore/cloud_firestore.dart';

class DateTimeUtils {
  DateTimeUtils._();

  static DateTime parseDate(dynamic date) {
    if (date is Timestamp) return date.toDate();
    if (date is String) {
      try {
        // Try parsing as ISO 8601 first
        return DateTime.parse(date);
      } catch (_) {
        try {
          // If that fails, try parsing as date-only format (YYYY-MM-DD)
          final parts = date.split('-');
          if (parts.length == 3) {
            return DateTime(
              int.parse(parts[0]),
              int.parse(parts[1]),
              int.parse(parts[2]),
            );
          }
        } catch (_) {
          // If all parsing fails, return now
        }
      }
    }
    return DateTime.now();
  }

  static DateTime? parseNullableDate(dynamic date) {
    if (date == null) return null;
    if (date is Timestamp) return date.toDate();
    if (date is String) {
      try {
        // Try parsing as ISO 8601 first
        return DateTime.parse(date);
      } catch (_) {
        try {
          // If that fails, try parsing as date-only format (YYYY-MM-DD)
          final parts = date.split('-');
          if (parts.length == 3) {
            return DateTime(
              int.parse(parts[0]),
              int.parse(parts[1]),
              int.parse(parts[2]),
            );
          }
        } catch (_) {
          // If all parsing fails, return null
        }
      }
    }
    return null;
  }
}
