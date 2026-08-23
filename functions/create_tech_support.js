const admin = require('firebase-admin');

admin.initializeApp();
const db = admin.firestore();

async function createTechSupport() {
  const phone = '01111111111'; // Example phone number
  const password = 'password123';
  const email = 'tech@switchpoint.com';
  
  // Create Firestore document
  const userDoc = {
    displayName: 'Technical Support',
    email: email,
    phoneNumber: phone,
    role: 'technical_support',
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    createdBy: 'system_script',
    password: password // Saving here to make sure fallback auth works
  };

  // Check if document already exists
  const snapshot = await db.collection('users').where('phoneNumber', '==', phone).limit(1).get();
  
  if (snapshot.empty) {
    const docRef = await db.collection('users').add(userDoc);
    console.log('Created Firestore user document with ID:', docRef.id);
  } else {
    const docId = snapshot.docs[0].id;
    await db.collection('users').doc(docId).update(userDoc);
    console.log('Updated Firestore user document with ID:', docId);
  }
  
  console.log('Done!');
  console.log(`\n-- Credentials --\nPhone: ${phone}\nPassword: ${password}`);
}

createTechSupport().catch(console.error);
