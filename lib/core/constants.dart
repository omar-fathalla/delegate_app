// lib/core/constants.dart

/// Attendance logs collection. The old `attendance_logs_testing` switch was
/// removed (TAS-339): it was always set to production since Feb 2026 and its
/// rules were dropped to keep the ruleset under the compile-time limit.
/// Kept for the debug banner in main.dart; the app always runs on production data.
const bool isProduction = true;

const String kAttendanceCollection = 'attendance_logs';

/// Attendance adjustments audit logs collection.
const String kAttendanceAdjustmentLogsCollection = 'attendance_adjustment_logs';
