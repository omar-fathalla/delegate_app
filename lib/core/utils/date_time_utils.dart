import 'package:cloud_firestore/cloud_firestore.dart';

class DateTimeUtils {
  DateTimeUtils._();

  static DateTime parseDate(dynamic date) {
    if (date is Timestamp) return date.toDate();
    if (date is String) return DateTime.parse(date);
    return DateTime.now();
  }

  static DateTime? parseNullableDate(dynamic date) {
    if (date == null) return null;
    if (date is Timestamp) return date.toDate();
    if (date is String) return DateTime.parse(date);
    return null;
  }
}
