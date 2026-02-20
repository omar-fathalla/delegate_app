// lib/core/constants.dart

/// Safe Toggle for Attendance System
///
/// When [isProduction] is true, attendance logs are written to the `attendance_logs` collection.
/// When [isProduction] is false, they are written to `attendance_logs_testing` to avoid polluting production data.
///
/// IMPORTANT: This should only be set to true after full verification.
const bool isProduction = false;

/// The name of the collection to store attendance logs.
/// Switches based on [isProduction].
const String kAttendanceCollection = isProduction
    ? 'attendance_logs'
    : 'attendance_logs_testing';
