// ignore_for_file: avoid_print
/// Firestore Data Seeder
///
/// Seeds the Firestore database with sample data for testing.
/// Run with: dart run scripts/seed_firestore.dart
///
/// Required: Firebase Admin SDK credentials.
/// For development, we use the Firebase emulator or direct Firestore access.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:delegate_app/firebase_options.dart';

Future<void> main() async {
  // Initialize Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final firestore = FirebaseFirestore.instance;

  print('🔥 Starting Firestore data seed...');

  // ---------- SEED USERS ----------
  print('👤 Seeding users collection...');

  // Check if test user already exists
  final existingUsers = await firestore
      .collection('users')
      .where('mobile', isEqualTo: '01012345678')
      .limit(1)
      .get();

  String testUserId;

  if (existingUsers.docs.isEmpty) {
    final userRef = await firestore.collection('users').add({
      'name': 'أحمد محمد',
      'mobile': '01012345678',
      'motherName': 'فاطمة',
      'role': 'delegate',
    });
    testUserId = userRef.id;
    print('  ✅ Created user: $testUserId');
  } else {
    testUserId = existingUsers.docs.first.id;
    print('  ℹ️  User already exists: $testUserId');
  }

  // ---------- SEED ATTENDANCE ----------
  print('📋 Seeding attendance collection...');

  // Check if attendance records already exist for this user
  final existingAttendance = await firestore
      .collection('attendance')
      .where('userId', isEqualTo: testUserId)
      .limit(1)
      .get();

  if (existingAttendance.docs.isEmpty) {
    final now = DateTime.now();

    // Create attendance records for the current month
    final attendanceRecords = [
      // Day 1 - الفرع الرئيسي
      {
        'userId': testUserId,
        'checkInTime': Timestamp.fromDate(
          DateTime(now.year, now.month, 1, 8, 0),
        ),
        'checkOutTime': Timestamp.fromDate(
          DateTime(now.year, now.month, 1, 17, 0),
        ),
        'latitude': 30.0444,
        'longitude': 31.2357,
        'branchName': 'الفرع الرئيسي',
        'imageUrl': null,
      },
      // Day 2 - الفرع الرئيسي
      {
        'userId': testUserId,
        'checkInTime': Timestamp.fromDate(
          DateTime(now.year, now.month, 2, 8, 30),
        ),
        'checkOutTime': Timestamp.fromDate(
          DateTime(now.year, now.month, 2, 16, 45),
        ),
        'latitude': 30.0444,
        'longitude': 31.2357,
        'branchName': 'الفرع الرئيسي',
        'imageUrl': null,
      },
      // Day 3 - فرع المعادي
      {
        'userId': testUserId,
        'checkInTime': Timestamp.fromDate(
          DateTime(now.year, now.month, 3, 9, 0),
        ),
        'checkOutTime': Timestamp.fromDate(
          DateTime(now.year, now.month, 3, 18, 0),
        ),
        'latitude': 29.9603,
        'longitude': 31.2497,
        'branchName': 'فرع المعادي',
        'imageUrl': null,
      },
      // Day 5 - الفرع الرئيسي
      {
        'userId': testUserId,
        'checkInTime': Timestamp.fromDate(
          DateTime(now.year, now.month, 5, 7, 45),
        ),
        'checkOutTime': Timestamp.fromDate(
          DateTime(now.year, now.month, 5, 17, 30),
        ),
        'latitude': 30.0444,
        'longitude': 31.2357,
        'branchName': 'الفرع الرئيسي',
        'imageUrl': null,
      },
      // Day 6 - فرع المعادي
      {
        'userId': testUserId,
        'checkInTime': Timestamp.fromDate(
          DateTime(now.year, now.month, 6, 8, 15),
        ),
        'checkOutTime': Timestamp.fromDate(
          DateTime(now.year, now.month, 6, 16, 15),
        ),
        'latitude': 29.9603,
        'longitude': 31.2497,
        'branchName': 'فرع المعادي',
        'imageUrl': null,
      },
      // Today - Active (no checkout) - الفرع الرئيسي
      {
        'userId': testUserId,
        'checkInTime': Timestamp.fromDate(
          DateTime(now.year, now.month, now.day, 8, 0),
        ),
        'checkOutTime': null,
        'latitude': 30.0444,
        'longitude': 31.2357,
        'branchName': 'الفرع الرئيسي',
        'imageUrl': null,
      },
    ];

    for (int i = 0; i < attendanceRecords.length; i++) {
      await firestore.collection('attendance').add(attendanceRecords[i]);
      print(
        '  ✅ Created attendance record ${i + 1}/${attendanceRecords.length}',
      );
    }
  } else {
    print('  ℹ️  Attendance records already exist for this user.');
  }

  print('');
  print('🎉 Seed complete!');
  print('');
  print('📋 Test credentials:');
  print('   Mobile:      01012345678');
  print('   Mother Name: فاطمة');
  print('   User ID:     $testUserId');
}
