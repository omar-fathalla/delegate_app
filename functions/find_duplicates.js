const { Firestore } = require('@google-cloud/firestore');

const db = new Firestore({
  projectId: 'practice-firebase-72df1',
});

async function findDuplicates() {
  console.log("Fetching users...");
  const usersRef = db.collection('users');
  const snapshot = await usersRef.get();
  const phoneMap = {};
  let totalCount = 0;
  
  snapshot.forEach(doc => {
    totalCount++;
    const data = doc.data();
    const phone = data.phoneNumber || data.phone;
    if (phone) {
      if (!phoneMap[phone]) phoneMap[phone] = [];
      phoneMap[phone].push({ id: doc.id, role: data.role || data.type || 'unknown', name: data.fullName || data.name || 'unknown' });
    }
  });

  console.log(`Total users checked: ${totalCount}`);

  const duplicates = Object.keys(phoneMap).filter(phone => phoneMap[phone].length > 1);
  console.log(`\nDuplicate phone numbers in 'users' collection: ${duplicates.length}\n`);
  
  duplicates.forEach(phone => {
    console.log(`Phone: ${phone}`);
    phoneMap[phone].forEach(doc => {
      console.log(`  - Doc ID: ${doc.id}, Role: ${doc.role}, Name: ${doc.name}`);
    });
    console.log('');
  });
}

findDuplicates().catch(console.error);
