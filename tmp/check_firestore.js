const fs = require('fs');
const https = require('https');
const config = JSON.parse(fs.readFileSync('/Users/fathalla/.config/configstore/firebase-tools.json', 'utf8'));
const accessToken = config.tokens.access_token;
const projectId = "practice-firebase-72df1";

const options = {
  hostname: 'firestore.googleapis.com',
  path: `/v1/projects/${projectId}/databases/(default)/documents:runQuery`,
  method: 'POST',
  headers: {
    'Authorization': `Bearer ${accessToken}`,
    'Content-Type': 'application/json'
  }
};

const req = https.request(options, (res) => {
  let body = '';
  res.on('data', d => body += d);
  res.on('end', () => console.log(body));
});

req.write(JSON.stringify({
  structuredQuery: {
    from: [{ collectionId: 'delegates', allDescendants: true }],
    where: {
      fieldFilter: {
        field: { fieldPath: 'phoneNumber' },
        op: 'EQUAL',
        value: { stringValue: '01287837426' }
      }
    },
    limit: 1
  }
}));
req.end();
