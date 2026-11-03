// lib/core/constants.dart

/// Safe Toggle for Attendance System
///
/// When [isProduction] is true, attendance logs are written to the `attendance_logs` collection.
/// When [isProduction] is false, they are written to `attendance_logs_testing` to avoid polluting production data.
///
/// IMPORTANT: This should only be set to true after full verification.
const bool isProduction = true;

/// Default organization (Fathalla Market) used when a user record has no
/// `organizationUID`. Single source for the previously hardcoded id.
const String kDefaultOrganizationId = 'PiioBFgxaHAeuRdjlDgj';

/// The name of the collection to store attendance logs.
/// Switches based on [isProduction].
/// Max age of an open check-in (no checkout) that HR screens still show as
/// "present now". Spans midnight on purpose (night shifts).
const Duration kAttendanceOngoingMaxDuration = Duration(hours: 11, minutes: 30);

const String kAttendanceCollection = isProduction
    ? 'attendance_logs'
    : 'attendance_logs_testing';

/// The name of the collection to store attendance adjustments audit logs.
/// Switches based on [isProduction].
const String kAttendanceAdjustmentLogsCollection = isProduction
    ? 'attendance_adjustment_logs'
    : 'attendance_adjustment_logs_testing';
