# Delegate subscriptions (feat/subscription-cycles)

Rules (Mohamed): periods H1 = 1 Jan–30 Jun, H2 = 1 Jul–31 Dec (Africa/Cairo).
500 EGP per delegate per period, prorated: `500 × remainingMonths / 6`, join
month counted in full, rounded half-up to 2 dp (500, 416.67, 333.33, 250,
166.67, 83.33). Free until the Cairo calendar day in `config/subscriptions.freePromotionLastDay` (fallback `2026-12-31`); first paid period 2027_H1. One
subscription per delegate covers every chain (add_organization is free).
Payment is online via Paymob only, charged once at registration/renewal.
Renewal creation: company supervisor and company admin (`UserRole.admin`;
supervisors share that role), HR (`UserRole.hr`), and org-admin
(`UserRole.organizationAdmin`) — the last only when the account has a
`companyUID` (fail-closed otherwise). Max **100** delegates per renewal
request (one Paymob charge). Stale quotes: `quoteSubscriptionRequest`
recomputes the amount when the calendar month changes in the same period
(500 × remaining months / 6) and writes it back on the request before
checkout; a period mismatch or a Paymob amount that does not match the
fresh quote is rejected and nobody is activated.

## Multi-chain new-delegate requests (Phase 1 item 3)

In the supervisor add-delegate form the chain picker is a multi-select with
«اختيار الكل». The company is the tenant: the supervisor can pick any of
their company's chains (up to 10). That produces **one** `delegate_requests`
document (`organizationUIDs` + singular `organizationUID` for the first
chain), **one** approval, and **one** subscription — the prorated fee is not
multiplied by the number of chains. Approval writes a chain doc under each
selected organization in the same `WriteBatch`.

If the person (national ID or phone) is already on a selected chain, or a
pending request already lists that chain, the chain is skipped and a warning
names the skipped and remaining chains. If every selected chain is a
duplicate, the request is not sent.

Older requests without `organizationUIDs` are still read as
`[organizationUID]`. The dry-run-first script
`functions/scripts/backfill-organization-uids.js` can fill the list on
tashil-dev (`--dry-run` then `--apply`, rollback file required). Run order and
GCP commands for Mohamed: `functions/scripts/README-organization-uids-backfill.md`.
Never prod without a written go.

## Paid add-to-another-chain (Phase 1 item 4)

A delegate who already has an **active** subscription can be added to another
chain of the same company with `requestType: add_organization`. That request
is never charged (`paymentStatus: not_required`, fee 0), whatever the client
passes. Approval copies the existing subscription mirror onto the new chain
doc and is refused if the delegate is not already active in the company, so
add-to-another-chain cannot be used to unsuspend without paying. Coverage and
renewal are per uid: one paid (or waived) request covers every chain, the
renewal list and fee count each uid once, and a verified payment reactivates
all of that uid's chain docs.


Same rules in two places, kept in sync by tests:
`lib/core/utils/subscription_cycle_helper.dart` (UI) and
`functions/src/subscription_logic.ts` (authoritative).

## Data

`delegate_requests/{id}` (existing collection), new fields:
`periodCode`, `amountDue`, `paymentStatus` (`pending|paid|failed|expired|waived|not_required`),
`paymob {transactionId, orderId, amountCents, currency, success, paidAt}`,
`paymentError`, `needsReview`, `applyState`.
Renewal (`requestType: "renewal"`): `coveredDelegateUids[]`, `items[{uid, fullName, fee}]`,
`periodStart`, `periodEnd`. One renewal = one Paymob payment for the selected delegates.

Delegate docs get a mirror `subscription {periodCode, periodStart, periodEnd, amountDue,
paymentStatus, renewalRequestId, registrationRequestId}`. Coverage is decided from
`delegate_requests` (rules-protected), never from this mirror.

**App-added delegate** = uid that is the doc id of an approved `new_delegate` request
with a `supervisorUid` (the app's registration flow). Angular/web delegates have no such
request and are never suspended.

## Server

- `suspendExpiredSubscriptions` (scheduled, 00:05 Africa/Cairo daily, codebase
  `tashil-mobile-notifications`): from 2027, suspends every app-added delegate (all its
  chain docs + `users/{uid}`) not covered by a paid request for the current period;
  `status: suspended`, `statusReason: subscription_expired`. After each period end,
  **15 Cairo calendar days of grace** apply (1–14 Jan and 1–14 Jul); suspension for
  the new half runs from **15 Jan** and **15 Jul**, not the 1st. Idempotent, batched
  (400), logged to `subscription_suspension_runs/{period}_{date}`. Never touches docs
  already suspended for another reason.
- `remindSupervisorsBeforeSubscriptionPeriodEnd` (00:08 Africa/Cairo daily): on the
  reminder day (default **14** Cairo days before 30 Jun and 31 Dec, overridable via
  `config/subscriptions.subscriptionReminderDays`) writes **one notification per live
  company supervisor per company per day**: uncovered delegates are grouped by
  **`companyUID` only** (tenant), not by org chain, so mixed or missing
  `organizationUID` on `delegate_requests` still yields a single reminder with the
  full uncovered count. When one company has **multiple org chains** on requests,
  every live supervisor on that company is notified once (no org filter on
  supervisor selection); `subscription_reminder_org_conflict` is logged with the
  org id set. Each active `supervisor` / `company_supervisor` /
  `company-supervisor` on that company gets `delegateUid` set to their uid (not the
  staff uid on `delegate_requests.supervisorUid`). Supervisors also read the shared
  inbox `delegateUid: supervisor_{companyUID}` in the app; when no live supervisor
  exists, the job writes only that fallback key. Supervisor lookup uses chunked
  Firestore `in` queries on `users.companyUID` and `users.companyId` (max 30 ids
  per query, no stacked role `in`, to stay under the 30-disjunction cap when many
  companies are due the same day); role and active-state filtering run in code.
  Failed lookup chunks are logged (`subscription_reminder_supervisor_lookup_failed`
  with `companyUIDs`; `fallbackDueToLookupFailure: true` when the shared inbox is
  used because lookup failed). When a `companyUID` chunk fails but `companyId`
  chunk still loads supervisors, `subscription_reminder_supervisor_lookup_partial`
  is logged with `supervisorRecipientCount` (live supervisor inboxes, not raw
  Firestore rows), and the job also writes one notification to
  `supervisor_{companyUID}` in addition to personal supervisor uids so
  company-keyed inboxes still see that day. Inactive / disabled / suspended /
  deleted supervisors
  are skipped. Counts app-added delegates lacking paid coverage for the **next**
  period. Run metrics: `supervisors` = distinct recipients, `companies` = companies
  with uncovered delegates, `notifications` = writes.
  Skipped when that **next** period is still free (its end day is on or before
  `freePromotionLastDay`), not merely because “today” is inside the promo window —
  so **17 Dec 2026** can remind for **2027_H1** while **16 Jun 2026** still skips
  for free **2026_H2**. Web-added delegates are excluded. Logged to
  `subscription_reminder_runs/{period}_{date}`.
- `quoteSubscriptionRequest(db, requestId, at)` → authoritative `amountCents`.
  The request's `periodCode` must be the current period, or the next period
  when advance renewal is open (see below). A future-period quote is computed
  at that period's start (full 500 EGP, not today's remaining months, and not
  zeroed by a free promotion that only covers today).
  Also checks the creator (`users/{supervisorUid}`): org and a non-empty company
  must match the request (super-admin is exempt). A uid already on another
  pending or paid renewal for the same period is rejected with `already_covered`
  (transactional claim in `subscription_coverage/{periodCode}_{uid}`). Cancelled,
  rejected, failed, or expired requests do not block a retry. A second partial
  renewal of other (uncovered) uids in the same period still works. The same
  pending request may be re-quoted (refreshing `quotedAt` and thus expiry).
- When staff reject (or cancel) a renewal, `finalizeTerminalRenewal` (and the
  `finalizeSubscriptionRenewalOnStatus` trigger) sets `paymentStatus` to
  `failed` with `paymentError: staff_rejected` (or `cancelled`) and releases
  the coverage claim so those delegates can be renewed again.
- Abandoned pending renewals expire at the earlier of quote validity (end of
  the Cairo month the quote was computed in, when the prorated fee would
  change) and the period end. `expireAbandonedSubscriptionRenewals` runs at
  00:10 Africa/Cairo daily; a quote transaction also lazily finalizes an
  expired (or rejected/cancelled-but-still-pending) other request so a new
  renewal can proceed without waiting for the job.
- `applyVerifiedSubscriptionPayment(db, payment)` → idempotent per Paymob transaction
  (`subscription_payment_events/{txId}`); on success marks the request paid and, for a
  current-period renewal, removes the expiry hold on `coveredDelegateUids` that were
  suspended for expiry. An advance payment for a future period writes coverage now
  and leaves the expiry hold in place (paying in November for January must not
  reactivate early). On failure or amount/period mismatch nobody is activated.
  The same coverage check runs so a uid cannot be charged twice.
  An advance (future-period) payment writes `nextSubscription` and leaves the
  current `subscription` map intact. `hasPaidCoverage` only counts a paid/waived
  map whose `periodCode` is the period being asked about (a prepaid 2027_H1
  does not cover November 2026). When that future period becomes current, M1
  promotes `nextSubscription` into `subscription` and deletes `nextSubscription`.
  In shadow mode a *current-period* paid renewal that leaves no holds also
  writes `status: active` and deletes `statusReason` on the delegate docs
  (same as the legacy path), so a paid delegate is not left suspended.
  `users/{uid}` is still not mirrored in shadow. An advance payment must not
  reactivate early.

## Advance renewal (`advanceRenewalEnabled`)

Off by default. `config/subscriptions` may set `advanceRenewalEnabled: true` and
`advanceRenewalDays` (default 30, max 180). When the flag is on, quotes for the
*next* period are accepted in the last N Cairo calendar days of the current
period (the period end day is included; the window closes at the period end).
The current period remains payable at any time.

`applyPaidRequest` only drops `subscription_expired` when the paid period is
the current one. When that future period starts, M1 skips uids already covered
by a paid/waived request and also removes a leftover expiry hold on those
app-added docs. In shadow mode this is a holds-only write (no status / no
`users/{uid}`).

Clients may read only `config/subscriptions` (signed-in, no writes). The app
reads `advanceRenewalEnabled` / `advanceRenewalDays` and `freePromotionLastDay` (Cairo `YYYY-MM-DD`, fallback `2026-12-31`) from that doc. Functions are authoritative for quotes; the app mirrors the date and uses TrustedTime for "now". After 2027-01-01 00:00 Africa/Cairo, rules reject new `waived` writes and unpaid `new_delegate` approvals. The same doc also falls
back to the compile-time default (`ENV=dev` on, 60 days; prod off, 30 days)
if the doc is missing or unreadable. A constructor override still wins in
tests. During the advance window the renewal screen lists both periods: the
current period stays renewable and cancellable (pending current-period
requests stay visible), and the next period is listed separately. One submit
is one period. This does not flip `HOLDS_AUTHORITY_MODE` and does not change
who may suspend.

## HOLDS_AUTHORITY_MODE (Phase 2 item 4)

`holdsMode()` reads `process.env.HOLDS_AUTHORITY_MODE`. Only the exact value
`authoritative` flips the writers; any other value (including unset, `shadow`,
or a typo) stays in shadow. Default is shadow.

Shadow writers may add or remove holds, `statusVersion`, and `statusHistory`,
but they do not write `status` or `statusReason` (except the existing M1/M2
prepaid / current-period renewal path that still reactivates a delegate when
the expiry hold is gone and no legacy non-expiry suspension remains). The
`auditDelegateHoldShadow` trigger only appends `status_audit`; it never
corrects status. `startBillingCycle` in shadow writes holds and priors on the
run doc, not company billing counters or `isPrinted`.

Authoritative mode additionally writes `status` / `statusReason` from the
holds map (`setDelegateHold`, and the M1/M2 library when those entry points
run) and lets `startBillingCycle` write company counters and `isPrinted`
(previous values stay on the `billing_cycles` run doc).

This flip does **not** deploy `suspendExpiredSubscriptions` (M1 is not live
on tashil-dev). `applyVerifiedSubscriptionPayment` is a Paymob library hook,
not a deployed tashil-dev function, so this env change does not by itself
alter a Paymob webhook in another service. `users/{uid}.status` is not
mirrored; `delegateLoginV2` and the app read the delegate document.

On tashil-dev only, after a written go (never prod, never together with a
`suspendExpiredSubscriptions` deploy):

```
bash scripts/holds_authority_mode.sh status --project tashil-dev
bash scripts/holds_authority_mode.sh flip --project tashil-dev
```

The script PATCHes `HOLDS_AUTHORITY_MODE` on the allowlisted functions
`setDelegateHold` and `startBillingCycle`. It does not upload source and it
refuses any project other than `tashil-dev`. After the flip, a `setDelegateHold`
call (even an unchanged one) should return `mode: "authoritative"`.

One-step rollback (same script, no source upload):

```
bash scripts/holds_authority_mode.sh rollback --project tashil-dev
```

That sets `HOLDS_AUTHORITY_MODE=shadow` on the same two functions. A later
`firebase deploy` of those functions can drop a hand-patched env var; run
`status` after any such deploy and re-apply if needed. Do not use this script
against prod.

Cloud Storage allows at most two `firestore.get`/`exists` calls per
request (same-document calls may be cached). `delegate_documents` is not
`isAuthenticated()`: anonymous tokens are denied, a folder owner may
access `delegate_documents/{uid}` with zero gets, and company staff / HR
/ org-admin may access a folder only when `storage_upload_intents/{id}`
exists and `companyUID` matches the caller (plus one get of
`users/{caller}`). Super-admin and technical support are global. There is
no empty-company fallback. Intents are created only by the `ensureStorageUploadIntent` callable, which verifies the folder's owning company (an existing `delegate_requests` doc or delegate uid) or reserves a new registration folder for the caller's company. Clients cannot mint intents (that was a first-come claim race). The app calls the callable before uploading. Same-company staff keep access to web/legacy uid folders after those uids are backfilled as intents. Payment receipts and the other Storage paths reject anonymous tokens. `companies/{compId}/**` is tenant-scoped to that company. `organizations/{org}/companies/{co}/**` is tenant-scoped by company (web ID-document paths stay the same). `staging/requests/{id}` uses the same intent check as `delegate_documents`. Delegates may upload permission photos under `organizations/{org}/companies/{co}/permissions/...` when the token `companyId` or `companyIds` matches; they may update or delete only `photo_{uid}_*` (or metadata userId/delegateUid). New clients write `photo_{uid}_{timestamp}.jpg`. Leave attachments under `leave_attachments/{companyUID}/{uid}/` are same-company for HR / supervisor / org-admin (or global) and the folder owner; accountant and marketing cannot use that path. Feedback screenshots stay on the flat `feedback_screenshots/{file}` path. Delegates may create only `feedback_{uid}_*` (the uid must be followed by `_`). Metadata `userId` is optional on create (live REST often omits it) but if present must equal the caller, including on read/update/delete of an existing object. Legacy objects that are not `feedback_{otherUid}_*` stay readable, updatable, or deletable when `userId` metadata equals the caller. New clients write `feedback_{uid}_{timestamp}.jpg`. Staff of any company can still read/write feedback (residual: no company segment). New penalty evidence is written to `penalties/{companyUID}/evidence/{penaltyId}/...` and is tenant-scoped. Legacy `penalties/evidence/{penaltyId}/...` stays readable by any named staff so existing objects keep working; new writes on the legacy path are denied. Accountant and marketing cannot read or write web ID-document paths. `public/` is world-readable; writes are staff-only. Intent reads no longer allow a missing doc, so 404 vs 403 cannot leak another company's folder. Request creates may not squat an id reserved by another company's intent. The registration form is reset after a successful submit.

Cross-service IAM is required for those gets: grant
`roles/firebaserules.firestoreServiceAgent` to
`service-<PROJECT_NUMBER>@gcp-sa-firebasestorage.iam.gserviceaccount.com`
(`--project tashil-dev` only unless Mohamed approves prod). Without that
role, Storage→Firestore gets deny and staff uploads fail. Prove with
`scripts/smoke_tashil_dev_storage_upload.js` (never against prod): staff
upload, anonymous deny, cross-company deny.

`startBillingCycle` caps `companyPriors` / `delegatePriors` on the run doc
at 100 entries and spills the rest to
`billing_cycles/{runId}/prior_shards/{shardId}`.

Org-admin create rules require `incomingOrgScoped()` and `incomingCompanyScoped()`
(cross-org create is denied; an org-admin with no companyUID cannot create). The
set of roles that may create renewals is unchanged.

**Dev-only free-period bypass (impossible on prod):** the server honors
`config/subscription_dev.bypassFreePeriodForCompanyUIDs` or a company doc
`subscriptionFreePeriodEnded: true` only when the Admin SDK `projectId` is
exactly `tashil-dev`. The same docs on `practice-firebase-72df1` are ignored.
The app honors the bypass only for `ENV=dev` and company `co_dev_renewal_paid`.

## Paymob checkout (test mode on tashil-dev)

Named functions (codebase `tashil-mobile-notifications`):

1. `createSubscriptionCheckout` (callable): the app sends only `requestId`. The
   function calls `quoteSubscriptionRequest`, creates a Paymob Intention for
   exactly `amountCents` EGP (`special_reference` = requestId), and returns the
   Unified Checkout URL. Live keys (`sk_live_` / `pk_live_` or `PAYMOB_LIVE=true`)
   are refused.
2. `paymobSubscriptionWebhook` (HTTPS): verifies the Transaction Processed HMAC
   (SHA-512, documented 20-field order) and calls
   `applyVerifiedSubscriptionPayment`. Failure or amount mismatch marks the
   request failed and releases coverage; nobody is activated. Success renews every
   covered uid atomically and idempotently (per Paymob transaction id).

Set test-mode env on the two functions only (never commit values):
`PAYMOB_SECRET_KEY` (`sk_test_…`), `PAYMOB_PUBLIC_KEY` (`pk_test_…`),
`PAYMOB_HMAC_SECRET`, `PAYMOB_INTEGRATION_IDS` (on tashil-dev use **5882985**
only — see `TASHIL_DEV_PAYMOB_INTEGRATION_ID`; never live `6033728`/`6033727`),
optional `PAYMOB_BASE_URL` (default `https://accept.paymob.com`).
The Flutter `PaymobSubscriptionGateway` calls (1) and never holds keys or amounts.

Nothing here is deployed. Before the scheduled function is deployed, the
`delegates.uid` collection-group field override in `firestore.indexes.json` and the
`delegate_requests` rule change must be live.
