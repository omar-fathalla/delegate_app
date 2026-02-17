import 'dart:convert';
import 'package:flutter/foundation.dart';

/// Safely parses the branch name from a QR code string.
///
/// Returns null if the string is not a valid JSON or doesn't match the expected structure:
/// {
///   "type": "attendance",
///   "branch": "BRANCH_NAME"
/// }
String? parseBranchFromQr(String rawValue) {
  try {
    final dynamic decoded = jsonDecode(rawValue);

    if (decoded is Map<String, dynamic> &&
        decoded['type'] == 'attendance') {
      if (decoded.containsKey('branch') &&
          decoded['branch'] is String) {
        return decoded['branch'] as String;
      }
    }
  } catch (e) {
    debugPrint('Error parsing QR: $e');
  }
  return null;
}
