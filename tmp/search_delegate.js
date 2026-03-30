const admin = require('firebase-admin');

// Note: This script assumes you are running in an environment where
// Google Application Default Credentials are set or you have a
// service-account key available.
// If not, it might fail.

if (!admin.apps.length) {
    admin.initializeApp({
        projectId: 'practice-firebase-72df1'
    });
}

const db = admin.firestore();

async function searchDelegate(phone, nationalId) {
    console.log(`Searching for Delegate: Phone=${phone}, NationalID=${nationalId}`);

    try {
        // 1. Search in users collection
        console.log('\n--- Searching users collection ---');
        const userQueryByPhone = await db.collection('users')
            .where('phoneNumber', '==', phone)
            .get();

        if (userQueryByPhone.empty) {
            console.log('No user found with this phone number.');
        } else {
            userQueryByPhone.forEach(doc => {
                console.log(`Found user by phone: ${doc.id}`);
                console.log(JSON.stringify(doc.data(), null, 2));
            });
        }

        const userQueryById = await db.collection('users')
            .where('nationalId', '==', nationalId)
            .get();

        if (userQueryById.empty) {
            console.log('No user found with this National ID.');
        } else {
            userQueryById.forEach(doc => {
                console.log(`Found user by National ID: ${doc.id}`);
                console.log(JSON.stringify(doc.data(), null, 2));
            });
        }

        // 2. Search for logs in collectionGroup('attendance_logs')
        console.log('\n--- Searching attendance_logs collectionGroup ---');
        const identifiers = [phone, nationalId];
        // If we found a UID, add it too
        userQueryByPhone.forEach(doc => identifiers.push(doc.id));
        userQueryById.forEach(doc => identifiers.push(doc.id));

        console.log(`Searching logs for identifiers: ${[...new Set(identifiers)]}`);

        const logsQuery = await db.collectionGroup('attendance_logs')
            .where('delegateId', 'in', [...new Set(identifiers)])
            .orderBy('timestamp', 'desc')
            .limit(10)
            .get();

        if (logsQuery.empty) {
            console.log('No attendance logs found for these identifiers in collectionGroup.');
        } else {
            console.log(`Found ${logsQuery.docs.length} logs.`);
            logsQuery.forEach(doc => {
                console.log(`Log ID: ${doc.id} | Path: ${doc.ref.path}`);
                console.log(JSON.stringify(doc.data(), null, 2));
            });
        }

    } catch (error) {
        console.error('Error during search:', error);
    }
}

const phone = '01206258026';
const nationalId = '29610211801346';

searchDelegate(phone, nationalId);
