const { execSync } = require('child_process');
const https = require('https');
const http = require('http');

const PROJECT_ID = 'delegate-app-ee931';

// Get access token from firebase CLI
function getAccessToken() {
    // Use firebase CLI to get a fresh access token
    const result = execSync('npx firebase-tools@latest login:ci --no-localhost 2>nul || echo ""', { encoding: 'utf-8' }).trim();
    // Fallback: use gcloud or firebase directly
    try {
        const token = execSync('firebase --token 2>nul', { encoding: 'utf-8' }).trim();
        return token;
    } catch (e) {
        return null;
    }
}

function firestoreUrl(path) {
    return `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/${path}`;
}

function makeRequest(method, url, data, token) {
    return new Promise((resolve, reject) => {
        const urlObj = new URL(url);
        const options = {
            hostname: urlObj.hostname,
            path: urlObj.pathname + urlObj.search,
            method,
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${token}`,
            },
        };
        const req = https.request(options, (res) => {
            let body = '';
            res.on('data', (chunk) => body += chunk);
            res.on('end', () => {
                try {
                    resolve({ status: res.statusCode, data: JSON.parse(body) });
                } catch (e) {
                    resolve({ status: res.statusCode, data: body });
                }
            });
        });
        req.on('error', reject);
        if (data) req.write(JSON.stringify(data));
        req.end();
    });
}

function toTimestamp(date) {
    return { timestampValue: date.toISOString() };
}

function toString(val) {
    return { stringValue: val };
}

function toDouble(val) {
    return { doubleValue: val };
}

function toNull() {
    return { nullValue: null };
}

async function seed() {
    console.log('🔑 Getting access token from Firebase CLI...');

    let token;
    try {
        // Try getting token using the firebase CLI internal approach
        token = execSync('node -e "const c=require(process.env.APPDATA+\'/npm/node_modules/firebase-tools/lib/configstore.js\');const s=c.default||c;console.log(s.get(\'tokens\').tokens.access_token||s.get(\'tokens\').tokens.refresh_token||\'\')"', { encoding: 'utf-8' }).trim();
    } catch (e) {
        console.log('  ⚠️ Could not get token from configstore, trying alternative...');
    }

    if (!token) {
        try {
            // Alternative: use the user field from firebase config
            token = execSync('node -e "const fs=require(\'fs\');const h=process.env.USERPROFILE||process.env.HOME;const c=JSON.parse(fs.readFileSync(h+\'/.config/configstore/firebase-tools.json\',\'utf8\'));console.log(c.tokens.access_token)"', { encoding: 'utf-8' }).trim();
        } catch (e) {
            console.log('  ⚠️ Could not get token from config file');
        }
    }

    if (!token) {
        console.error('❌ Could not get access token. Please run: firebase login');
        process.exit(1);
    }

    console.log('  ✅ Got access token');
    console.log('');
    console.log('🔥 Starting Firestore data seed...');

    // ---------- SEED USERS ----------
    console.log('👤 Seeding users collection...');

    // List existing users
    const listRes = await makeRequest('GET',
        `${firestoreUrl('users')}?pageSize=100`, null, token);

    let testUserId = null;

    if (listRes.status === 200 && listRes.data.documents) {
        for (const doc of listRes.data.documents) {
            const fields = doc.fields || {};
            if (fields.mobile && fields.mobile.stringValue === '01012345678') {
                testUserId = doc.name.split('/').pop();
                console.log(`  ℹ️  User already exists: ${testUserId}`);
                break;
            }
        }
    }

    if (!testUserId) {
        const createRes = await makeRequest('POST', firestoreUrl('users'), {
            fields: {
                name: toString('أحمد محمد'),
                mobile: toString('01012345678'),
                motherName: toString('فاطمة'),
                role: toString('delegate'),
            }
        }, token);

        if (createRes.status === 200 || createRes.status === 201) {
            testUserId = createRes.data.name.split('/').pop();
            console.log(`  ✅ Created user: ${testUserId}`);
        } else {
            console.error('  ❌ Failed to create user:', JSON.stringify(createRes.data));
            process.exit(1);
        }
    }

    // ---------- SEED ATTENDANCE ----------
    console.log('📋 Seeding attendance collection...');

    // Check if attendance exists
    // Use structured query to filter by userId
    const queryRes = await makeRequest('POST',
        `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents:runQuery`,
        {
            structuredQuery: {
                from: [{ collectionId: 'attendance' }],
                where: {
                    fieldFilter: {
                        field: { fieldPath: 'userId' },
                        op: 'EQUAL',
                        value: toString(testUserId),
                    }
                },
                limit: 1,
            }
        }, token);

    const hasAttendance = queryRes.status === 200 && Array.isArray(queryRes.data)
        && queryRes.data.length > 0 && queryRes.data[0].document;

    if (!hasAttendance) {
        const now = new Date();
        const year = now.getFullYear();
        const month = now.getMonth();

        const records = [
            { day: 1, hIn: 8, mIn: 0, hOut: 17, mOut: 0, branch: 'الفرع الرئيسي', lat: 30.0444, lng: 31.2357 },
            { day: 2, hIn: 8, mIn: 30, hOut: 16, mOut: 45, branch: 'الفرع الرئيسي', lat: 30.0444, lng: 31.2357 },
            { day: 3, hIn: 9, mIn: 0, hOut: 18, mOut: 0, branch: 'فرع المعادي', lat: 29.9603, lng: 31.2497 },
            { day: 5, hIn: 7, mIn: 45, hOut: 17, mOut: 30, branch: 'الفرع الرئيسي', lat: 30.0444, lng: 31.2357 },
            { day: 6, hIn: 8, mIn: 15, hOut: 16, mOut: 15, branch: 'فرع المعادي', lat: 29.9603, lng: 31.2497 },
            { day: 9, hIn: 8, mIn: 0, hOut: 17, mOut: 0, branch: 'الفرع الرئيسي', lat: 30.0444, lng: 31.2357 },
            { day: 10, hIn: 8, mIn: 30, hOut: 16, mOut: 30, branch: 'فرع المعادي', lat: 29.9603, lng: 31.2497 },
            { day: 12, hIn: 7, mIn: 50, hOut: 17, mOut: 20, branch: 'الفرع الرئيسي', lat: 30.0444, lng: 31.2357 },
            { day: 13, hIn: 9, mIn: 0, hOut: 17, mOut: 0, branch: 'فرع مدينة نصر', lat: 30.0511, lng: 31.3656 },
        ];

        for (let i = 0; i < records.length; i++) {
            const r = records[i];
            const checkIn = new Date(year, month, r.day, r.hIn, r.mIn);
            const checkOut = new Date(year, month, r.day, r.hOut, r.mOut);

            const res = await makeRequest('POST', firestoreUrl('attendance'), {
                fields: {
                    userId: toString(testUserId),
                    checkInTime: toTimestamp(checkIn),
                    checkOutTime: toTimestamp(checkOut),
                    latitude: toDouble(r.lat),
                    longitude: toDouble(r.lng),
                    branchName: toString(r.branch),
                }
            }, token);

            if (res.status === 200 || res.status === 201) {
                console.log(`  ✅ Created attendance record ${i + 1}/${records.length} (Day ${r.day})`);
            } else {
                console.error(`  ❌ Failed record ${i + 1}:`, JSON.stringify(res.data).substring(0, 200));
            }
        }

        // Today - active (no checkout)
        const todayCheckIn = new Date(year, month, now.getDate(), 8, 0);
        const todayRes = await makeRequest('POST', firestoreUrl('attendance'), {
            fields: {
                userId: toString(testUserId),
                checkInTime: toTimestamp(todayCheckIn),
                latitude: toDouble(30.0444),
                longitude: toDouble(31.2357),
                branchName: toString('الفرع الرئيسي'),
            }
        }, token);

        if (todayRes.status === 200 || todayRes.status === 201) {
            console.log(`  ✅ Created active check-in (today, no checkout)`);
        } else {
            console.error('  ❌ Failed active record:', JSON.stringify(todayRes.data).substring(0, 200));
        }

    } else {
        console.log('  ℹ️  Attendance records already exist for this user.');
    }

    console.log('');
    console.log('🎉 Seed complete!');
    console.log('');
    console.log('📋 Test credentials:');
    console.log('   Mobile:      01012345678');
    console.log(`   Mother Name: فاطمة`);
    console.log(`   User ID:     ${testUserId}`);
}

seed().catch(console.error);
