---
description: Implement or modify the attendance check-in/check-out feature with geo-fencing, anti-fraud, and server timestamp rules.
---

# Attendance Check-In/Check-Out Implementation

## Anti-Fraud Rules (Mandatory)

These rules MUST be followed for every attendance-related operation:

1. **Server Timestamp Only:** NEVER use `DateTime.now()` for check-in/check-out times. Always use `FieldValue.serverTimestamp()`.
2. **Location Verification:** Verify the delegate's GPS coordinates match the assigned worksite BEFORE submitting to Firestore.
3. **Mock Location Detection:** Check for mock/fake location providers and reject if detected.

## 1. Location Verification

Use the `geolocator` package to:

```dart
import 'package:geolocator/geolocator.dart';

// 1. Check permissions
final permission = await Geolocator.checkPermission();

// 2. Get current position
final position = await Geolocator.getCurrentPosition(
  desiredAccuracy: LocationAccuracy.high,
);

// 3. Check for mock location (Anti-Fraud)
if (position.isMocked) {
  return Left(LocationFraudFailure());
}

// 4. Calculate distance to worksite
final distance = Geolocator.distanceBetween(
  position.latitude, position.longitude,
  worksite.latitude, worksite.longitude,
);

// 5. Verify within geo-fence radius (e.g., 100 meters)
if (distance > allowedRadius) {
  return Left(OutOfRangeFailure());
}
```

## 2. Submitting Check-In to Firestore

```dart
// ✅ CORRECT: Server timestamp
await firestore
  .collection('organizations').doc(orgId)
  .collection('companies').doc(compId)
  .collection('delegates').doc(uid)
  .collection('attendance').add({
    'checkInTime': FieldValue.serverTimestamp(),  // Server time!
    'latitude': position.latitude,
    'longitude': position.longitude,
    'status': 'checkedIn',
    'uid': currentUser.uid,
  });

// ❌ WRONG: Never do this
// 'checkInTime': DateTime.now().toIso8601String(),
```

## 3. Check-Out Flow

Same verification steps as check-in, then update the existing attendance record:

```dart
await attendanceDocRef.update({
  'checkOutTime': FieldValue.serverTimestamp(),
  'checkOutLatitude': position.latitude,
  'checkOutLongitude': position.longitude,
  'status': 'checkedOut',
});
```

## 4. Offline Consideration

- Attendance actions **require internet** to guarantee server timestamp integrity.
- If implementing offline queuing for remote areas:
  - Record the local timestamp as `localCheckInTime` (for display only).
  - Sync to Firestore when online, using `FieldValue.serverTimestamp()` for the official `checkInTime`.
  - Clearly indicate "pending sync" status in the UI.

## 5. Bloc Events & States

```dart
// Events
CheckInRequested(String worksiteId)
CheckOutRequested(String attendanceRecordId)

// States
AttendanceInitial
AttendanceLoading
CheckInSuccess(AttendanceRecord record)
CheckOutSuccess(AttendanceRecord record)
AttendanceError(String message)   // Arabic-friendly error messages
LocationVerifying
OutOfRange(double distance)
```

## 6. Permissions Check

Ensure the delegate can only submit attendance for themselves:
- Use `currentUser.uid` from Firebase Auth.
- The Firestore path must include their own UID.
- Never allow querying attendance records of other delegates.
