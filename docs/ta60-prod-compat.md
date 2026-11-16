# TA-60 prod rules compatibility (delegate_app)

**PR:** https://github.com/omar-fathalla/delegate_app/pull/343  
**Integrator branch:** `cursor/ta60-prod-compat-9a4a` → base `dev`  
**Worker branch (Stream 1 closures):** `cursor/ta60-w1-closures`  
**Live baseline:** ruleset **4daaee78** (`test/rules/ta60/live.rules`, `live.storage.rules`)

> **No merge/deploy.** Function code and rules land on this branch only until Mohamed approves prod steps below.

## Head SHA

| Branch | SHA | Note |
|--------|-----|------|
| `cursor/ta60-prod-compat-9a4a` | **`31e0444d`** | Mohamed gate: docs 443/443, matrix 22/22, prod-compat 0 unexpected |
| `cursor/ta60-w1-closures` | `dc71a4b` | Closure classification (39 NOTIF as a,b) |

## C1 — `invite_email_index` (not auth `inviteId` claim)

| Piece | Detail |
|---|---|
| Index doc | `invite_email_index/{lowercasedEmail}` → `{ inviteId, organizationUID, companyUID, role, status: pending }` |
| Maintainers | `onInviteEmailIndexSync` on `invites/{inviteId}` (`tashil-mobile-notifications` codebase); backfill `functions/scripts/backfill-invite-email-index.js` (**dry-run default**, `--project` required) |
| Client access | **No** client read/write on index (`allow read, write: if false`); rules correlate via `get(/invite_email_index/$(authEmailLower()))` + existing batch `getAfter` on `/invites/{inviteId}` |
| Web | **No** web changes; batch seeds index in tests, **no** `inviteId` custom claim |

### Prod deploy order (Mohamed)

1. **Targeted function deploy** (isolated codebase only):
   `firebase deploy --only functions:tashil-mobile-notifications:onInviteEmailIndexSync --project <project>`
2. **Backfill** pending invites (dry-run first):
   `node functions/scripts/backfill-invite-email-index.js --project tashil-dev`  
   Prod: explicit go + `--allow-prod-project=practice-firebase-72df1 --apply`
3. **Deploy `firestore.rules`** with C1 hardened `claimInvite$` paths.  
   Deploying rules **before** index + backfill breaks live web claim batches.

Storage: index is Firestore-only; `storage.rules` documents that (no Storage paths).

## TA-60 prod-compat harness

| Suite | cases | unexpected | deliberate |
|---|---:|---:|---:|
| Firestore | **239** | **0** | **5** (2 class-(c) + 3 silent class-(d) in `DELIBERATE_FIRESTORE_REGRESSIONS`; FS-11–18 class **(b)** via `globalStaffUnbatched*` bell shapes) |
| Storage | **22** | **0** | 0 |

`npm run test:rules:prod-compat` → **2/2** pass @ **`31e0444d`** (set `LOCAL_CI_LOGGING_PORT` if hub/logging ports collide on shared CI hosts).

### Rules matrix (22 suites)

`bash scripts/run_rules_matrix.sh` @ **`31e0444d`**: all **PASS** (`test:rules:docs` **443/443**, `test:rules:source` **9/9**, `test:rules:m31` **13/13**, …).  
Extra (not in matrix): `npm run test:rules:ta60-supervisor-dup` — **PASS** on integrator VM.

### Docs-pending TA-60 alignment

`test/rules/docs-pending.test.js` uses `unbatchedBatchParity` / `compatNo` for live 1.14.3 batch quirks and five **TA-60 no-op guards** where batched add_org or lone approve would hit the expression budget; unbatched approve/provision remains covered by `firestore_compat.mjs` (FS-11–18). Details: store `internal/ta60-final-integrate-report.md`.

Regenerate closure table (requires Firestore emulator): `node scripts/ta60_closure_table.mjs` (via `scripts/emulators_exec.sh`).

## Rules verified (agent VM, C1 pass)

| npm script | result |
|---|---|
| `test:rules:invite-claim` | **9/9** (index seed, no token claim; deny without index) |
| `test:rules:p0` | **13/13** |
| `test:rules:adv` | **11/11** |
| `test:rules:prod-compat` | **2/2** (FS **0** unexpected, ST **0**) |
| `functions` `invite_email_index_logic` unit | pass (after `npm run build`) |

Expr-budget: harness treats emulator text `Unable to evaluate the expression as the maximum of 1000 expressions to evaluate has been reached` (and legacy `limit exceeded`) as **unexpected** expression-limit failures, distinct from intentional DENY.

## Firestore deliberate closures (59) — classification @ harness `9f86350`

**Harness:** `test/rules/ta60/firestore_compat.mjs` vs `live.rules` (ruleset 4daaee78). Deliberate = `isDeliberateFirestoreRegression()` (20 named + 39 `list bell:`).

| Class | Meaning | Count |
|-------|---------|------:|
| **(a,b)** | Live web tashil **and** store app **1.14.3** (all **39** `NOTIF-READ` bell list rows — user-visible) | 39 |
| **(b)** | Store app **1.14.3** only (non-bell), incl. TS/SA unbatched approve+provision | 9 |
| **(c)** | **≤1.14.1** / anonymous only | 2 |
| **(d)** | Silent / partial degrade (try/catch only; **not** bell lists or global-staff approve) | 9 |

### Visibility audit — class **(d)** rows (15)

Code references: `lib/features/notifications/data/datasources/notification_remote_data_source.dart` (`queryAllSettled`), `lib/features/admin/data/chain_duplicate_lookup.dart` (fail-closed), `delegate_subscription_repository_impl.dart` @ **cb3f4e2** (1.14.3 **unbatched** approve), **8f698e93** (batched r4 on `main`). Suspend/hold: client `update` paths — **1.14.3 does not ship `setDelegateHold`** (callable lands 2026-11-11+).

| ID | Harness case | Web visible? | App 1.14.3 visible? | Verdict | Action |
|----|--------------|--------------|---------------------|---------|--------|
| FS-01 | delegate CG `nationalityID` (try/catch) | No (web N/A) | No — login is phone CG + `delegate_login_api`; harness is secondary | **OK (d)** | None |
| FS-02 | delegate `users` by supervisor phone | No | No — supervisor home contact card lookup in `catch (_) {}` (not attendance notify fan-out) | **OK (d)** | None |
| FS-03 | supervisor CG phone dup-check | No | **Yes** — `DuplicateChainLookupException` snackbar | **MISCLASS → (b)** | Stream 2 **P2** org-scoped dup list |
| FS-04 | supervisor CG nationalId dup-check | No | **Yes** | **MISCLASS → (b)** | Stream 2 **P2** |
| FS-05 | supervisor CG receiptCode dup-check | No | **Yes** | **MISCLASS → (b)** | Stream 2 **P2** |
| FS-06 | supervisor `delegate_requests` receiptCode | No | **Yes** | **MISCLASS → (b)** | Stream 2 **P3a** |
| FS-07 | supervisor `users` role notify | No | No — penalty notify wrapped in `catch (_) {}`; primary staff path is `listGlobalNotifyStaff` (TA-35) | **OK (d)** | None |
| FS-08 | supervisor company broadcast notif **read** | **Yes** (partial bell) | **Yes** (partial bell) | **MISCLASS → (a,b)** | Stream 2 **P0-A** (same as NOTIF bell) |
| FS-09 | supervisor delegate **suspend** update | Depends on web direct write | **Yes** — 1.14.3 may use client nested `update` (no `setDelegateHold` yet) | **(b)** | **Stream 2** narrow nested **ALLOW** |
| FS-11 | TS approve unbatched | No | **Yes** — cb3f4e2 unbatched `delegate_requests` update | **(b)** → **ALLOW** (`globalStaffUnbatchedRequestApproveOk`) | Stream B3 |
| FS-12 | SA approve unbatched | No | **Yes** | **(b)** → **ALLOW** | Stream B3 |
| FS-13 | TS provision step2c unbatched | No | **Yes** — cb3f4e2 separate delegate set(merge) | **(b)** → **ALLOW** (`globalStaffUnbatchedDelegateProvisionOk`) | Stream B3 |
| FS-15 | URG supervisor broadcast notif **read** | **Yes** | **Yes** | **MISCLASS → (a,b)** | Stream 2 **P0-A** |
| FS-16 | URG TS approve step1 unbatched | No | **Yes** | **(b)** → **ALLOW** | Stream B3 |
| FS-17 | URG TS step2c unbatched | No | **Yes** | **(b)** → **ALLOW** | Stream B3 |
| FS-18 | URG SA approve step1 unbatched | No | **Yes** | **(b)** → **ALLOW** | Stream B3 |

**Audit summary**

| Verdict | IDs | Count |
|---------|-----|------:|
| Confirmed silent **(d)** | FS-01, FS-02, FS-07 | **3** |
| **(b)** prod-compat (app 1.14.3 + rules restored) | FS-11–13, FS-16–18 | **6** |
| **Misclassified** (need Firebase fix, not silent) | FS-03–06 → **(b)**; FS-08, FS-15 → **(a,b)** | **6** |
| FS-09 | Callable-safe on app; rules **ALLOW** landing in Stream 2 for harness/web suspend write | **1** |

Keep main table **(d)** labels until integrator merges Stream 2; use this audit for fix priority.

### Mohamed decision — unsafe (a)/(b) without safe Firebase-only path (**no widen**)

| ID | Harness case | Screen / flow | Blocker |
|----|--------------|---------------|---------|
| FS-09 | supervisor update delegate doc status (suspend) | Supervisor delegate suspend/hold | **Stream 2 in progress:** narrow nested status ALLOW. App **1.14.3 (cb3f4e2)** has no `setDelegateHold` — suspend may use client nested `update` until callable ships. |

### Full closure table

| ID | Area | Harness case | Class | Screen / flow | Firebase-only keep working? | Decision |
|----|------|--------------|-------|---------------|----------------------------|----------|
| FS-01 | APP-D | delegate CG delegates where nationalityID == own (identifier resolve, try/catch) | (d) | Delegate login / identifier resolve (OTP path fallback) | Yes — partial degrade; app uses queryAllSettled / login fallbacks | — |
| FS-02 | APP-D | delegate users where phoneNumber == supervisorPhone | (d) | Delegate supervisor home contact card lookup (try/catch) | Yes — partial degrade; app uses queryAllSettled / login fallbacks | — |
| FS-03 | APP-S | supervisor CG delegates phoneNumber dup-check (try/catch) | (d) | Supervisor new-delegate registration dup check | Yes — narrow org-scoped CG/delegate_requests list (Stream 2 / P2–P3a; no REQUEST CHANGES widen) | — |
| FS-04 | APP-S | supervisor CG delegates nationalId dup-check (try/catch) | (d) | Supervisor new-delegate registration dup check | Yes — narrow org-scoped CG/delegate_requests list (Stream 2 / P2–P3a; no REQUEST CHANGES widen) | — |
| FS-05 | APP-S | supervisor CG delegates receiptCode dup-check (try/catch) | (d) | Supervisor new-delegate registration receipt dup | Yes — narrow org-scoped CG/delegate_requests list (Stream 2 / P2–P3a; no REQUEST CHANGES widen) | — |
| FS-06 | APP-S | supervisor delegate_requests where receiptCode (try/catch) | (d) | Supervisor registration receiptCode dup | Yes — narrow org-scoped CG/delegate_requests list (Stream 2 / P2–P3a; no REQUEST CHANGES widen) | — |
| FS-07 | APP-S | supervisor users where role in [super-admin...] (notify, try/catch) | (d) | Penalty fan-out staff lookup | Yes — `listGlobalNotifyStaff` callable (live TA-35); rules deny client enumerate | — |
| FS-08 | APP-S | supervisor read company broadcast notifications (delegateUid in [supervisor_co, company_co]) | (d) | Supervisor notification bell (company broadcasts) | Yes — P0-A notification list wiring; bell merges via `queryAllSettled` (other uid queries may still succeed) | — |
| FS-09 | APP-S | supervisor update delegate doc status (suspend) | (b) | Supervisor delegate suspend/hold | Stream 2 narrow nested ALLOW; 1.14.3 client update until `setDelegateHold` (post-1.14.3) | Stream 2 ALLOW |
| FS-10 | RC | supervisor registration nationalId dup-check listen (nationalId query) | (b) | Supervisor registration realtime dup listener | Yes — org-scoped CG dup list (P2) | — |
| FS-11 | APP-S | tech support approve request (update status approved) | (b) | TS approve subscription request | Yes — `globalStaffUnbatchedRequestApproveOk` (app cb3f4e2 unbatched; batched r4 path unchanged) | Stream B3 |
| FS-12 | APP-S | super-admin approve request (update status approved, main step 1) | (b) | SA approve subscription request | Yes — same | Stream B3 |
| FS-13 | APP-S | tech support provision delegate set(merge) status active (main step 2c, unbatched) | (b) | TS provision delegate step 2c | Yes — `globalStaffUnbatchedDelegateProvisionOk` | Stream B3 |
| FS-14 | APP-S | any staff users list all (private label perms: users get()) | (b) | Private Label hub user search | Yes — replace with scoped `users` list by role/org (private-label search); not full collection scan | — |
| FS-15 | URG | supervisor read company broadcasts delegateUid in [supervisor_co, company_co, all_company_supervisors] | (d) | Supervisor notification bell broadcasts | Yes — P0-A notification list wiring; bell merges via `queryAllSettled` (other uid queries may still succeed) | — |
| FS-16 | URG | ts approve new delegate step1 update delegate_requests approved | (b) | TS approve step1 | Yes — Stream B3 unbatched global-staff path | Stream B3 |
| FS-17 | URG | ts approve step2c delegate set(merge) active | (b) | TS provision step2c | Yes — Stream B3 | Stream B3 |
| FS-18 | URG | sa approve new delegate step1 update delegate_requests approved | (b) | SA approve step1 | Yes — Stream B3 | Stream B3 |
| FS-19 | NOTIF-READ | oa list bell: delegateUid==all (limit 30) | (a,b) | Org-admin notification bell (live web tashil + app) | Yes — Stream 2 P0-A split cheap scoped `allow list` on `/notifications`; restores bell without REQUEST CHANGES widen | — |
| FS-20 | NOTIF-READ | oa list bell: delegateUid==organizationAdmin (limit 30) | (a,b) | Org-admin notification bell (live web tashil + app) | Yes — Stream 2 P0-A split cheap scoped `allow list` on `/notifications`; restores bell without REQUEST CHANGES widen | — |
| FS-21 | NOTIF-READ | oa list bell: delegateUid==company_coA (limit 30) | (a,b) | Org-admin notification bell (live web tashil + app) | Yes — Stream 2 P0-A split cheap scoped `allow list` on `/notifications`; restores bell without REQUEST CHANGES widen | — |
| FS-22 | NOTIF-READ | oa list bell: companyId+all_company_supervisors (limit 30) | (a,b) | Org-admin notification bell (live web tashil + app) | Yes — Stream 2 P0-A split cheap scoped `allow list` on `/notifications`; restores bell without REQUEST CHANGES widen | — |
| FS-23 | NOTIF-READ | oa list bell: delegateUid==hr (limit 30) | (a,b) | Org-admin notification bell (live web tashil + app) | Yes — Stream 2 P0-A split cheap scoped `allow list` on `/notifications`; restores bell without REQUEST CHANGES widen | — |
| FS-24 | NOTIF-READ | oa list bell: delegateUid==delegates_coA (limit 30) | (a,b) | Org-admin notification bell (live web tashil + app) | Yes — Stream 2 P0-A split cheap scoped `allow list` on `/notifications`; restores bell without REQUEST CHANGES widen | — |
| FS-25 | NOTIF-READ | ca list bell: delegateUid==all (limit 30) | (a,b) | ca staff notification bell (web where applicable + app 1.14.3) | Yes — Stream 2 P0-A split cheap scoped `allow list` on `/notifications`; restores bell without REQUEST CHANGES widen | — |
| FS-26 | NOTIF-READ | ca list bell: delegateUid==company_coA (limit 30) | (a,b) | ca staff notification bell (web where applicable + app 1.14.3) | Yes — Stream 2 P0-A split cheap scoped `allow list` on `/notifications`; restores bell without REQUEST CHANGES widen | — |
| FS-27 | NOTIF-READ | ca list bell: delegateUid==hr (limit 30) | (a,b) | ca staff notification bell (web where applicable + app 1.14.3) | Yes — Stream 2 P0-A split cheap scoped `allow list` on `/notifications`; restores bell without REQUEST CHANGES widen | — |
| FS-28 | NOTIF-READ | ca list bell: delegateUid==delegates_coA (limit 30) | (a,b) | ca staff notification bell (web where applicable + app 1.14.3) | Yes — Stream 2 P0-A split cheap scoped `allow list` on `/notifications`; restores bell without REQUEST CHANGES widen | — |
| FS-29 | NOTIF-READ | sup list bell: delegateUid==all (limit 30) | (a,b) | sup staff notification bell (web where applicable + app 1.14.3) | Yes — Stream 2 P0-A split cheap scoped `allow list` on `/notifications`; restores bell without REQUEST CHANGES widen | — |
| FS-30 | NOTIF-READ | sup list bell: delegateUid==company_coA (limit 30) | (a,b) | sup staff notification bell (web where applicable + app 1.14.3) | Yes — Stream 2 P0-A split cheap scoped `allow list` on `/notifications`; restores bell without REQUEST CHANGES widen | — |
| FS-31 | NOTIF-READ | sup list bell: delegateUid==hr (limit 30) | (a,b) | sup staff notification bell (web where applicable + app 1.14.3) | Yes — Stream 2 P0-A split cheap scoped `allow list` on `/notifications`; restores bell without REQUEST CHANGES widen | — |
| FS-32 | NOTIF-READ | sup list bell: delegateUid==delegates_coA (limit 30) | (a,b) | sup staff notification bell (web where applicable + app 1.14.3) | Yes — Stream 2 P0-A split cheap scoped `allow list` on `/notifications`; restores bell without REQUEST CHANGES widen | — |
| FS-33 | NOTIF-READ | hr list bell: delegateUid==all (limit 30) | (a,b) | hr staff notification bell (web where applicable + app 1.14.3) | Yes — Stream 2 P0-A split cheap scoped `allow list` on `/notifications`; restores bell without REQUEST CHANGES widen | — |
| FS-34 | NOTIF-READ | hr list bell: delegateUid==hr (limit 30) | (a,b) | hr staff notification bell (web where applicable + app 1.14.3) | Yes — Stream 2 P0-A split cheap scoped `allow list` on `/notifications`; restores bell without REQUEST CHANGES widen | — |
| FS-35 | NOTIF-READ | hr list bell: delegateUid==company_coA (limit 30) | (a,b) | hr staff notification bell (web where applicable + app 1.14.3) | Yes — Stream 2 P0-A split cheap scoped `allow list` on `/notifications`; restores bell without REQUEST CHANGES widen | — |
| FS-36 | NOTIF-READ | hr list bell: delegateUid==hr (limit 30) | (a,b) | hr staff notification bell (web where applicable + app 1.14.3) | Yes — Stream 2 P0-A split cheap scoped `allow list` on `/notifications`; restores bell without REQUEST CHANGES widen | — |
| FS-37 | NOTIF-READ | hr list bell: delegateUid==delegates_coA (limit 30) | (a,b) | hr staff notification bell (web where applicable + app 1.14.3) | Yes — Stream 2 P0-A split cheap scoped `allow list` on `/notifications`; restores bell without REQUEST CHANGES widen | — |
| FS-38 | NOTIF-READ | acc list bell: delegateUid==all (limit 30) | (a,b) | acc staff notification bell (web where applicable + app 1.14.3) | Yes — Stream 2 P0-A split cheap scoped `allow list` on `/notifications`; restores bell without REQUEST CHANGES widen | — |
| FS-39 | NOTIF-READ | acc list bell: delegateUid==company_coA (limit 30) | (a,b) | acc staff notification bell (web where applicable + app 1.14.3) | Yes — Stream 2 P0-A split cheap scoped `allow list` on `/notifications`; restores bell without REQUEST CHANGES widen | — |
| FS-40 | NOTIF-READ | acc list bell: delegateUid==hr (limit 30) | (a,b) | acc staff notification bell (web where applicable + app 1.14.3) | Yes — Stream 2 P0-A split cheap scoped `allow list` on `/notifications`; restores bell without REQUEST CHANGES widen | — |
| FS-41 | NOTIF-READ | acc list bell: delegateUid==delegates_coA (limit 30) | (a,b) | acc staff notification bell (web where applicable + app 1.14.3) | Yes — Stream 2 P0-A split cheap scoped `allow list` on `/notifications`; restores bell without REQUEST CHANGES widen | — |
| FS-42 | NOTIF-READ | mkt list bell: delegateUid==all (limit 30) | (a,b) | mkt staff notification bell (web where applicable + app 1.14.3) | Yes — Stream 2 P0-A split cheap scoped `allow list` on `/notifications`; restores bell without REQUEST CHANGES widen | — |
| FS-43 | NOTIF-READ | mkt list bell: delegateUid==marketing (limit 30) | (a,b) | mkt staff notification bell (web where applicable + app 1.14.3) | Yes — Stream 2 P0-A split cheap scoped `allow list` on `/notifications`; restores bell without REQUEST CHANGES widen | — |
| FS-44 | NOTIF-READ | mkt list bell: delegateUid==company_coA (limit 30) | (a,b) | mkt staff notification bell (web where applicable + app 1.14.3) | Yes — Stream 2 P0-A split cheap scoped `allow list` on `/notifications`; restores bell without REQUEST CHANGES widen | — |
| FS-45 | NOTIF-READ | mkt list bell: companyId+all_company_supervisors (limit 30) | (a,b) | mkt staff notification bell (web where applicable + app 1.14.3) | Yes — Stream 2 P0-A split cheap scoped `allow list` on `/notifications`; restores bell without REQUEST CHANGES widen | — |
| FS-46 | NOTIF-READ | mkt list bell: delegateUid==hr (limit 30) | (a,b) | mkt staff notification bell (web where applicable + app 1.14.3) | Yes — Stream 2 P0-A split cheap scoped `allow list` on `/notifications`; restores bell without REQUEST CHANGES widen | — |
| FS-47 | NOTIF-READ | mkt list bell: delegateUid==delegates_coA (limit 30) | (a,b) | mkt staff notification bell (web where applicable + app 1.14.3) | Yes — Stream 2 P0-A split cheap scoped `allow list` on `/notifications`; restores bell without REQUEST CHANGES widen | — |
| FS-48 | NOTIF-READ | mp list bell: delegateUid==all (limit 30) | (a,b) | mp staff notification bell (web where applicable + app 1.14.3) | Yes — Stream 2 P0-A split cheap scoped `allow list` on `/notifications`; restores bell without REQUEST CHANGES widen | — |
| FS-49 | NOTIF-READ | mp list bell: delegateUid==marketing_promotion (limit 30) | (a,b) | mp staff notification bell (web where applicable + app 1.14.3) | Yes — Stream 2 P0-A split cheap scoped `allow list` on `/notifications`; restores bell without REQUEST CHANGES widen | — |
| FS-50 | NOTIF-READ | mp list bell: delegateUid==company_coA (limit 30) | (a,b) | mp staff notification bell (web where applicable + app 1.14.3) | Yes — Stream 2 P0-A split cheap scoped `allow list` on `/notifications`; restores bell without REQUEST CHANGES widen | — |
| FS-51 | NOTIF-READ | mp list bell: companyId+all_company_supervisors (limit 30) | (a,b) | mp staff notification bell (web where applicable + app 1.14.3) | Yes — Stream 2 P0-A split cheap scoped `allow list` on `/notifications`; restores bell without REQUEST CHANGES widen | — |
| FS-52 | NOTIF-READ | mp list bell: delegateUid==hr (limit 30) | (a,b) | mp staff notification bell (web where applicable + app 1.14.3) | Yes — Stream 2 P0-A split cheap scoped `allow list` on `/notifications`; restores bell without REQUEST CHANGES widen | — |
| FS-53 | NOTIF-READ | mp list bell: delegateUid==delegates_coA (limit 30) | (a,b) | mp staff notification bell (web where applicable + app 1.14.3) | Yes — Stream 2 P0-A split cheap scoped `allow list` on `/notifications`; restores bell without REQUEST CHANGES widen | — |
| FS-54 | NOTIF-READ | bm list bell: delegateUid==all (limit 30) | (a,b) | bm staff notification bell (web where applicable + app 1.14.3) | Yes — Stream 2 P0-A split cheap scoped `allow list` on `/notifications`; restores bell without REQUEST CHANGES widen | — |
| FS-55 | NOTIF-READ | bm list bell: delegateUid==company_coA (limit 30) | (a,b) | bm staff notification bell (web where applicable + app 1.14.3) | Yes — Stream 2 P0-A split cheap scoped `allow list` on `/notifications`; restores bell without REQUEST CHANGES widen | — |
| FS-56 | NOTIF-READ | bm list bell: delegateUid==hr (limit 30) | (a,b) | bm staff notification bell (web where applicable + app 1.14.3) | Yes — Stream 2 P0-A split cheap scoped `allow list` on `/notifications`; restores bell without REQUEST CHANGES widen | — |
| FS-57 | NOTIF-READ | bm list bell: delegateUid==delegates_coA (limit 30) | (a,b) | bm staff notification bell (web where applicable + app 1.14.3) | Yes — Stream 2 P0-A split cheap scoped `allow list` on `/notifications`; restores bell without REQUEST CHANGES widen | — |
| FS-58 | APP-OLD | anonymous (<=v1.14.1) CG delegates phone login query | (c) | Legacy anonymous phone login | n/a (intentional close) | — |
| FS-59 | APP-OLD | anonymous (<=v1.14.1) add attendance check-in | (c) | Legacy anonymous attendance write | n/a (intentional close) | — |

**Notes**
- **NOTIF-READ (39):** All classified **(a,b)** — denied bell queries are **user-visible** (missing broadcasts on live web + app 1.14.3). **Stream 2** delivers P0-A scoped list ALLOW fixes; no reclassify as **(d)**.
- **Approve / provision (6):** **(b)** for 1.14.3 — app **cb3f4e2** uses unbatched TS/SA writes; rules restored via `globalStaffUnbatched*Ok()` (WriteBatch r4 on **main** / **8f698e93** unchanged).
- **Dup-check try/catch (5):** UI fails closed on total deny — audit marks **(b)**, not **(d)**; Stream 2 **P2/P3a** restores org-scoped lists.
- **FS-08 / FS-15:** Supervisor broadcast **read** shapes are bell merges — audit marks **(a,b)** like NOTIF; covered by Stream 2 **P0-A**.

## Deferred / M3

Attendance marketing/supervisor org-branch list shapes and related comments remain as in rules (`attendanceMarketingOrgListOk`, `attendanceSupervisorOrgBranchListOk`); full M3 prod-compat expansion tracked separately in REQUEST CHANGES brief.

## Next

- Stream 2: REQUEST CHANGES rules (H3–M6, LOW) without widening closures above
- Full **~20-suite** rules matrix on Mac mirror / CI when ports stable
- **No** merge, **no** prod or tashil-dev deploy without explicit ask
