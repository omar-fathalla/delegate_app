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

Same rules in two places, kept in sync by tests:
`lib/core/utils/subscription_cycle_helper.dart` (UI) and
`functions/src/subscription_logic.ts` (authoritative).

## Data

`delegate_requests/{id}` (existing collection), new fields:
`periodCode`, `amountDue`, `paymentStatus` (`pending|paid|failed|waived|not_required`),
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
- `applyVerifiedSubscriptionPayment(db, payment)` → idempotent per Paymob transaction
  (`subscription_payment_events/{txId}`); on success marks the request paid and, for a
  renewal, reactivates only `coveredDelegateUids` that were suspended for expiry. On
  failure or amount/period mismatch nobody is activated.

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
