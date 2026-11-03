# Rollback record: interim prod Firestore rules hardening

Approved by Mohamed (2026-11-04 00:49 Cairo): prepare and test on dev; **production deploy only after his separate approval**. Nothing in this PR touches production.

## What changes
`firestore/interim-prod-hardening.rules` = live prod ruleset `44ad81d0` verbatim, plus `request.auth != null` (`isAuthenticated()`) on:
- `users/{userId}` read (writes already required auth)
- `attendance_logs/{document=**}` read/create/update (delete stays `false`)
- `organizations/{orgId}/attendance_logs/{logId}` read/create/update (delete stays `false`)
- `leave_requests/{requestId}` read/write
- `delegate_tracking/{delegateId}` and `.../breadcrumbs/{id}` read/write
- `delegates` collectionGroup: already `isAuthenticated()` in 44ad81d0, unchanged.

Anonymous / custom-token / email sessions keep exactly the 44ad81d0 access.

## Production (practice-firebase-72df1): baseline to restore
- Live release: `projects/practice-firebase-72df1/releases/cloud.firestore`
- Ruleset: `projects/practice-firebase-72df1/rulesets/44ad81d0-d1a8-4e27-b9fe-5eecb824453d`
- Ruleset createTime: 2026-10-08T07:12:17Z (2026-10-08 09:12 Cairo); release updateTime 2026-10-08T07:12:18Z
- Verbatim copy: `test/rules/fixtures/prod-44ad81d0.rules`

Re-release 44ad81d0 (instant, no redeploy of anything else):
```bash
TOKEN=$(gcloud auth print-access-token)
curl -s -X PATCH \
  -H "Authorization: Bearer $TOKEN" -H "x-goog-user-project: practice-firebase-72df1" \
  -H "Content-Type: application/json" \
  -d '{"release":{"name":"projects/practice-firebase-72df1/releases/cloud.firestore","rulesetName":"projects/practice-firebase-72df1/rulesets/44ad81d0-d1a8-4e27-b9fe-5eecb824453d"}}' \
  https://firebaserules.googleapis.com/v1/projects/practice-firebase-72df1/releases/cloud.firestore
```
Alternative: Firebase console → Firestore → Rules → history → 44ad81d0 → "Restore".
Do NOT use `firebase deploy --only firestore:rules` for rollback: firebase.json points at the repo `firestore.rules` (different, newer rules).

## tashil-dev (dev test)
- Previous release before this test: `projects/tashil-dev/rulesets/c1cdae43-8745-4db3-ab0c-0f3521d04eef` (created 2026-11-03T18:45:38Z = 20:45 Cairo; repo firestore.rules from dev)
- Released for this test: `projects/tashil-dev/rulesets/a0b599df-ac20-4328-bcc1-45e32a5718c9` (2026-11-04 00:52 Cairo)

Restore the previous tashil-dev ruleset:
```bash
TOKEN=$(gcloud auth print-access-token)
curl -s -X PATCH \
  -H "Authorization: Bearer $TOKEN" -H "x-goog-user-project: tashil-dev" \
  -H "Content-Type: application/json" \
  -d '{"release":{"name":"projects/tashil-dev/releases/cloud.firestore","rulesetName":"projects/tashil-dev/rulesets/c1cdae43-8745-4db3-ab0c-0f3521d04eef"}}' \
  https://firebaserules.googleapis.com/v1/projects/tashil-dev/releases/cloud.firestore
```

## Verification after any release
Unauthenticated REST list must be 403 for users/attendance_logs/leave_requests/delegate_tracking and 200 for an unchanged open collection (e.g. organizations):
```bash
curl -s -o /dev/null -w '%{http_code}\n' "https://firestore.googleapis.com/v1/projects/<PROJECT>/databases/(default)/documents/users?pageSize=1"
```
Emulator proof: `npm run test:rules:interim` (192 cases vs 44ad81d0, 0 unexpected diffs).
