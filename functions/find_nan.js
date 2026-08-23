const admin = require('firebase-admin');

// Initialize Firebase Admin (assuming default credentials via gcloud)
admin.initializeApp();
const db = admin.firestore();

async function checkNaN(collectionPath) {
    console.log(`Checking ${collectionPath}...`);
    const snapshot = await db.collectionGroup(collectionPath).get();
    
    for (const doc of snapshot.docs) {
        const data = doc.data();
        let hasIssue = false;
        
        for (const [key, value] of Object.entries(data)) {
            if (typeof value === 'number' && isNaN(value)) {
                console.log(`FOUND NaN in ${collectionPath}: doc ${doc.id} key ${key}`);
                hasIssue = true;
            }
        }
    }
}

async function main() {
    await checkNaN('photo_permissions');
    await checkNaN('captured_photos');
    await checkNaN('delegates');
    await checkNaN('users');
    console.log('Done checking.');
}

main().catch(console.error);
