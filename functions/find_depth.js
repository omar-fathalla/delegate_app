const admin = require('firebase-admin');

admin.initializeApp();
const db = admin.firestore();

function getDepth(obj) {
    if (obj === null || typeof obj !== 'object') {
        return 0;
    }
    if (obj instanceof Date || obj instanceof admin.firestore.Timestamp || obj instanceof admin.firestore.GeoPoint) {
        return 0;
    }
    let max = 0;
    for (const key of Object.keys(obj)) {
        const depth = getDepth(obj[key]);
        if (depth > max) {
            max = depth;
        }
    }
    return max + 1;
}

async function checkDepth(collectionPath) {
    console.log(`Checking ${collectionPath}...`);
    const snapshot = await db.collectionGroup(collectionPath).get();
    
    for (const doc of snapshot.docs) {
        const data = doc.data();
        const depth = getDepth(data);
        if (depth > 10) {
            console.log(`Deep nesting in ${collectionPath}: doc ${doc.id}, depth ${depth}`);
        }
    }
}

async function main() {
    await checkDepth('photo_permissions');
    await checkDepth('captured_photos');
    await checkDepth('delegates');
    await checkDepth('users');
    console.log('Done checking depth.');
}

main().catch(console.error);
