# Subscription Phase 0 — production deploy & rollback (Mohamed)

**Scope:** prepare on `tashil-dev` only in this PR. **Do not** deploy to `practice-firebase-72df1` until Mohamed approves a separate production window. **Do not** deploy `suspendExpiredSubscriptions` in Phase 0.

## Preconditions

- Web portal repo (TE-36): stop deploying Firestore rules / indexes from Angular `firebase.json` so mobile rules remain the single source of truth.
- Confirm Paymob webhook and Engineering endpoints are ready before enabling paid subscriptions on prod.
- Export baseline ruleset IDs from Firebase console (Firestore → Rules → history) immediately before deploy.

## Deploy order (future prod)

Deploy in this order so clients never hit missing indexes or rules that reject legitimate staff flows.

1. **Indexes** (additive only; build time 5–30+ minutes on large tenants)
   ```bash
   cd delegate_app
   firebase deploy --only firestore:indexes --project practice-firebase-72df1
   ```
   Wait until all new indexes show **Enabled** in console (especially collection group `requests`: `ttlAt`, `status` + `updatedAt`; `delegates.uid` field override must already exist).

2. **Firestore rules** (`firestore.rules` on `dev` after this PR merges)
   ```bash
   firebase deploy --only firestore:rules --project practice-firebase-72df1
   ```

3. **Cloud Functions** (codebase `tashil-mobile-notifications` only — never blanket `firebase deploy --only functions`)
   ```bash
   firebase deploy --only functions:tashil-mobile-notifications \
     --project practice-firebase-72df1
   ```
   **Exclude** `suspendExpiredSubscriptions` until subscription billing is fully signed off:
   ```bash
   firebase deploy --only functions:tashil-mobile-notifications:createStaffUser,functions:tashil-mobile-notifications:resendStaffSetupLink,functions:tashil-mobile-notifications:claimInvite,functions:tashil-mobile-notifications:delegateLoginV2,functions:tashil-mobile-notifications:confirmDelegateOtp,functions:tashil-mobile-notifications:staffPhoneLookup,functions:tashil-mobile-notifications:onTaskCreated,functions:tashil-mobile-notifications:onTaskUpdated,functions:tashil-mobile-notifications:onPhotoPermissionCreated,functions:tashil-mobile-notifications:onPhotoPermissionUpdated,functions:tashil-mobile-notifications:onNotificationCreated \
     --project practice-firebase-72df1
   ```
   **Blocker (Phase 0):** prod also runs `completeStaffPasswordSetup`, `requestStaffPasswordReset`, and `sendStaffPasswordSetupEmail`, which are not yet in this repository. Do not run a codebase-wide functions deploy until those exports are recovered from prod source and reviewed; otherwise Firebase will delete the live endpoints.

4. **Storage rules** (only if this PR changes `storage.rules`)
   ```bash
   firebase deploy --only storage --project practice-firebase-72df1
   ```

## tashil-dev validation (this PR)

```bash
firebase deploy --only firestore:rules,firestore:indexes --project tashil-dev
# Functions: same targeted list as prod, on tashil-dev, still excluding suspendExpiredSubscriptions
npm run test:rules:subs
npm run test:rules:docs
npm --prefix functions test
npm run test:e2e:staff
```

Record ruleset ID and deploy timestamp in this file after dev deploy.

## Rollback (prod)

### Firestore rules (fastest — ruleset re-release)

Do **not** rollback by deploying an old git branch unless intentional. Prefer re-releasing the pre-deploy ruleset:

```bash
TOKEN=$(gcloud auth print-access-token)
curl -s -X PATCH \
  -H "Authorization: Bearer $TOKEN" -H "x-goog-user-project: practice-firebase-72df1" \
  -H "Content-Type: application/json" \
  -d '{"release":{"name":"projects/practice-firebase-72df1/releases/cloud.firestore","rulesetName":"projects/practice-firebase-72df1/rulesets/<PREVIOUS_RULESET_ID>"}}' \
  https://firebaserules.googleapis.com/v1/projects/practice-firebase-72df1/releases/cloud.firestore
```

Live prod baseline reference: `test/rules/fixtures/prod-44ad81d0.rules` (ruleset `44ad81d0-d1a8-4e27-b9fe-5eecb824453d`, see `docs/rollback/interim-prod-rules.md`).

### Indexes

Index deploys are additive; rollback is usually **not** required. If a new composite causes query failures, remove the offending index entry from `firestore.indexes.json`, redeploy indexes, and fix client queries.

### Functions

Re-deploy the previous function bundle from the last known good git tag, or restore individual functions from GCP console revisions. Never delete unrelated functions in the shared GCP project.

## Rules summary (Phase 0 delta vs prod `44ad81d0`)

### `delegate_requests`

| Action | Allowed | Denied |
|--------|---------|--------|
| **Read** | Super-admin, technical support; org-admin **in same org**; company-admin / supervisor / HR **in same org+company**; supervisor who submitted (`supervisorUid`); delegate owner (`delegateUid` or doc id) | Any authenticated user (prod); cross-company org-admin / supervisor / HR; delegates reading others’ requests |
| **Create** | Super-admin; org-admin / company-admin / HR naming self as `supervisorUid`; pending payment fields on staff-created renewals | Client sets `paymentStatus: paid`, `paymob`, or flips paid on create |
| **Update** | Staff review fields; cancel unpaid; legacy approve/reject; self doc uploads on own request id | Payment tampering; `applyState` / `paymentError` / `needsReview` from client; mutating paid quote fields |
| **Delete** | Super-admin; org-admin | Everyone else |

### Public / `if true` audit (prod fixture → current `firestore.rules`)

Prod `44ad81d0` had ~30 `allow … if true` (and `read, write: if isAuthenticated()` on `delegate_requests`). Current rules keep **one** intentional public read:

| Location | Prod (`44ad81d0`) | Phase 0 (`firestore.rules`) | Notes |
|----------|-------------------|-------------------------------|--------|
| `invites/{id}` **get** | `if true` | `if true` | **Kept** — unguessable id for signup |
| `invites` list | open / loose | signed-in staff scoped | **Tightened** |
| `penalties`, `penalty_rules`, CG penalties | `if true` | signed-in / staff writers | **Tightened** |
| `notifications`, `sent_notifications` | `if true` | signed-in scoped | **Tightened** |
| `delegate_requests` | `isAuthenticated()` read+write | scoped read; staff create/update + payment guard | **Tightened** |
| `monthly_collections`, wallets, billing children | `if true` | accountant / org-admin / global staff | **Tightened** |
| Collection-group duplicates with `if true` | several | removed (single CG match) | **Tightened** — see comment at CG overlaps |
| `organizations` / `companies` / `users` top-level | various open reads | signed-in + role helpers | **Tightened** |
| `storage.rules` `feedback_screenshots` read | `if true` | `if true` (storage, not Firestore) | **Kept** per product policy |

Run `npm run test:rules:interim` to prove interim hardening still matches the 44ad81d0 auth-gate intent on the collections that were hot-fixed on prod.

## Flows that may break after prod deploy

- **Anonymous sessions:** already blocked by modern rules; ensure no production flows still use anonymous auth.
- **Cross-company staff listing `delegate_requests`:** supervisors admins or HR in company A can no longer read company B requests (intended).
- **Delegates** can read only their own request doc, not staff queues.
- **Client-side payment marking:** Paymob webhook + Admin SDK must be live before enforcing paid renewals.
- **Collection group `requests` queries** using `ttlAt` or `status`+`updatedAt` fail until indexes finish building.
- **Staff password callables** missing from repo: web/mobile flows that call the three prod-only functions remain dependent on prod binaries until source is recovered.

## Contacts

- Deploy approval: Mohamed  
- Paymob / Engineering webhook: per `docs/SUBSCRIPTIONS.md`
