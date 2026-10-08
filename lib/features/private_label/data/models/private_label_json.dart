import 'package:cloud_firestore/cloud_firestore.dart';

/// Shared parsing helpers for Private Label models (Firestore + local JSON).
abstract final class PrivateLabelJson {
  static DateTime? parseDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static double? parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.replaceAll(',', '.'));
    return null;
  }

  static int parseInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static String parseString(dynamic value) => value?.toString() ?? '';

  static String? parseNullableString(dynamic value) {
    final s = value?.toString();
    return (s == null || s.isEmpty) ? null : s;
  }

  static List<String> parseStringList(dynamic value) {
    if (value is List) return value.map((e) => e.toString()).toList();
    return const [];
  }
}
