const { initializeApp, applicationDefault, cert } = require('firebase-admin/app');
const { getFirestore, Timestamp } = require('firebase-admin/firestore');

// Initialize with default credentials (uses GOOGLE_APPLICATION_CREDENTIALS or firebase login)
initializeApp({ projectId: 'delegate-app-ee931' });
const db = getFirestore();

async function seed() {
    console.log('🔥 Starting Firestore data seed...');

    // ---------- SEED USERS ----------
    console.log('👤 Seeding users collection...');

    const usersRef = db.collection('users');
    const existingUsers = await usersRef.where('mobile', '==', '01012345678').limit(1).get();

    let testUserId;

    if (existingUsers.empty) {
        const userDoc = await usersRef.add({
            name: 'أحمد محمد',
            mobile: '01012345678',
            motherName: 'فاطمة',
            role: 'delegate',
        });
        testUserId = userDoc.id;
        console.log(`  ✅ Created user: ${testUserId}`);
    } else {
        testUserId = existingUsers.docs[0].id;
        console.log(`  ℹ️  User already exists: ${testUserId}`);
    }

    // ---------- SEED ATTENDANCE ----------
    console.log('📋 Seeding attendance collection...');

    const attendanceRef = db.collection('attendance');
    const existingAttendance = await attendanceRef.where('userId', '==', testUserId).limit(1).get();

    if (existingAttendance.empty) {
        const now = new Date();
        const year = now.getFullYear();
        const month = now.getMonth(); // 0-indexed

        const records = [
            // Day 1 - الفرع الرئيسي
            {
                userId: testUserId,
                checkInTime: Timestamp.fromDate(new Date(year, month, 1, 8, 0)),
                checkOutTime: Timestamp.fromDate(new Date(year, month, 1, 17, 0)),
                latitude: 30.0444,
                longitude: 31.2357,
                branchName: 'الفرع الرئيسي',
                imageUrl: null,
            },
            // Day 2 - الفرع الرئيسي
            {
                userId: testUserId,
                checkInTime: Timestamp.fromDate(new Date(year, month, 2, 8, 30)),
                checkOutTime: Timestamp.fromDate(new Date(year, month, 2, 16, 45)),
                latitude: 30.0444,
                longitude: 31.2357,
                branchName: 'الفرع الرئيسي',
                imageUrl: null,
            },
            // Day 3 - فرع المعادي
            {
                userId: testUserId,
                checkInTime: Timestamp.fromDate(new Date(year, month, 3, 9, 0)),
                checkOutTime: Timestamp.fromDate(new Date(year, month, 3, 18, 0)),
                latitude: 29.9603,
                longitude: 31.2497,
                branchName: 'فرع المعادي',
                imageUrl: null,
            },
            // Day 5 - الفرع الرئيسي
            {
                userId: testUserId,
                checkInTime: Timestamp.fromDate(new Date(year, month, 5, 7, 45)),
                checkOutTime: Timestamp.fromDate(new Date(year, month, 5, 17, 30)),
                latitude: 30.0444,
                longitude: 31.2357,
                branchName: 'الفرع الرئيسي',
                imageUrl: null,
            },
            // Day 6 - فرع المعادي
            {
                userId: testUserId,
                checkInTime: Timestamp.fromDate(new Date(year, month, 6, 8, 15)),
                checkOutTime: Timestamp.fromDate(new Date(year, month, 6, 16, 15)),
                latitude: 29.9603,
                longitude: 31.2497,
                branchName: 'فرع المعادي',
                imageUrl: null,
            },
            // Day 9 - الفرع الرئيسي
            {
                userId: testUserId,
                checkInTime: Timestamp.fromDate(new Date(year, month, 9, 8, 0)),
                checkOutTime: Timestamp.fromDate(new Date(year, month, 9, 17, 0)),
                latitude: 30.0444,
                longitude: 31.2357,
                branchName: 'الفرع الرئيسي',
                imageUrl: null,
            },
            // Day 10 - فرع المعادي
            {
                userId: testUserId,
                checkInTime: Timestamp.fromDate(new Date(year, month, 10, 8, 30)),
                checkOutTime: Timestamp.fromDate(new Date(year, month, 10, 16, 30)),
                latitude: 29.9603,
                longitude: 31.2497,
                branchName: 'فرع المعادي',
                imageUrl: null,
            },
            // Day 12 - الفرع الرئيسي
            {
                userId: testUserId,
                checkInTime: Timestamp.fromDate(new Date(year, month, 12, 7, 50)),
                checkOutTime: Timestamp.fromDate(new Date(year, month, 12, 17, 20)),
                latitude: 30.0444,
                longitude: 31.2357,
                branchName: 'الفرع الرئيسي',
                imageUrl: null,
            },
            // Day 13 - فرع مدينة نصر
            {
                userId: testUserId,
                checkInTime: Timestamp.fromDate(new Date(year, month, 13, 9, 0)),
                checkOutTime: Timestamp.fromDate(new Date(year, month, 13, 17, 0)),
                latitude: 30.0511,
                longitude: 31.3656,
                branchName: 'فرع مدينة نصر',
                imageUrl: null,
            },
            // Today - Active (no checkout) - الفرع الرئيسي
            {
                userId: testUserId,
                checkInTime: Timestamp.fromDate(new Date(year, month, now.getDate(), 8, 0)),
                checkOutTime: null,
                latitude: 30.0444,
                longitude: 31.2357,
                branchName: 'الفرع الرئيسي',
                imageUrl: null,
            },
        ];

        const batch = db.batch();
        for (const record of records) {
            batch.set(attendanceRef.doc(), record);
        }
        await batch.commit();
        console.log(`  ✅ Created ${records.length} attendance records`);
    } else {
        console.log('  ℹ️  Attendance records already exist.');
    }

    console.log('');
    console.log('🎉 Seed complete!');
    console.log('');
    console.log('📋 Test credentials:');
    console.log('   Mobile:      01012345678');
    console.log('   Mother Name: فاطمة');
    console.log(`   User ID:     ${testUserId}`);
}

seed().catch(console.error);
