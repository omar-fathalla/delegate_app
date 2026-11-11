# Delegate subscriptions (feat/subscription-cycles)

Rules (Mohamed): periods H1 = 1 Jan–30 Jun, H2 = 1 Jul–31 Dec (Africa/Cairo).
500 EGP per delegate per period, prorated: `500 × remainingMonths / 6`, join
month counted in full, rounded half-up to 2 dp (500, 416.67, 333.33, 250,
166.67, 83.33). Free until 2026-12-31; first paid period 2027_H1. One
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
tashil-dev (rollback file required; no prod apply without a written go).

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
  `status: suspended`, `statusReason: subscription_expired`. Idempotent, batched (400),
  logged to `subscription_suspension_runs/{period}_{date}`. Never touches docs already
  suspended for another reason.
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
reads `advanceRenewalEnabled` / `advanceRenewalDays` from that doc and falls
back to the compile-time default (`ENV=dev` on, 60 days; prod off, 30 days)
if the doc is missing or unreadable. A constructor override still wins in
tests. During the advance window the renewal screen lists both periods: the
current period stays renewable and cancellable (pending current-period
requests stay visible), and the next period is listed separately. One submit
is one period. This does not flip `HOLDS_AUTHORITY_MODE` and does not change
who may suspend.

Cloud Storage allows at most two `firestore.get`/`exists` calls per
request (same-document calls may be cached). `delegate_documents` is not
`isAuthenticated()`: anonymous tokens are denied, a folder owner may
access `delegate_documents/{uid}` with zero gets, and company staff / HR
/ org-admin may access a folder only when `storage_upload_intents/{id}`
exists and `companyUID` matches the caller (plus one get of
`users/{caller}`). Super-admin and technical support are global. There is
no empty-company fallback. Intents are created only by the `ensureStorageUploadIntent` callable, which verifies the folder's owning company (an existing `delegate_requests` doc or delegate uid) or reserves a new registration folder for the caller's company. Clients cannot mint intents (that was a first-come claim race). The app calls the callable before uploading. Same-company staff keep access to web/legacy uid folders after those uids are backfilled as intents. Payment receipts and the other Storage paths reject anonymous tokens. `companies/{compId}/**` is tenant-scoped to that company.

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

## What Engineering's Paymob module must provide

1. A server endpoint that creates the Paymob order for a `requestId`: call
   `quoteSubscriptionRequest`, charge exactly `amountCents` in EGP, put `requestId` in
   the order (`merchant_order_id` or extras), return the checkout URL.
2. Paymob webhook (transaction processed callback): verify the HMAC with the secret from
   Secret Manager, then call `applyVerifiedSubscriptionPayment` with
   `{requestId, paymobTransactionId, paymobOrderId, success, amountCents, currency, paidAt}`.
3. A Dart `SubscriptionPaymentGateway` implementation calling (1); register it in
   `injection_container.dart` instead of `PaymobNotConnectedGateway`.
4. Keys (API key, integration id, iframe id, HMAC secret) only in Secret Manager /
   function config. Never in the app or this repo.

Nothing here is deployed. Before the scheduled function is deployed, the
`delegates.uid` collection-group field override in `firestore.indexes.json` and the
`delegate_requests` rule change must be live.
