const admin = require('firebase-admin');

admin.initializeApp();
const db = admin.firestore();

async function findTechSupport() {
  const snapshot = await db.collection('users').where('role', '==', 'technical_support').limit(1).get();
  
  if (snapshot.empty) {
    console.log('No matching documents.');
    return;
  }  

  snapshot.forEach(doc => {
    const data = doc.data();
    console.log('ID:', doc.id);
    console.log('Phone:', data.phoneNumber);
    console.log('Password (password):', data.password);
    console.log('Password (temporaryPassword):', data.temporaryPassword);
    console.log('Password (tempPassword):', data.tempPassword);
    console.log('Email:', data.email);
  });
}

findTechSupport().catch(console.error);
