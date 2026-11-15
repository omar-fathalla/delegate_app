# Task F — Group renewal (one Paymob payment)

Mohamed batch ops for **tashil-dev only**. Never prod (`practice-firebase-72df1`).
Use the **merge commit SHA** of PR #305 into `dev` before deploy or User Test sign-off.

## Checkout

```bash
git fetch origin dev
git checkout <MERGE_SHA>
cd functions && npm ci
```

## Paymob test integration (Mohamed machine only)

- `PAYMOB_INTEGRATION_IDS=5882985` (test). Never live ids `6033728` / `6033727`.
- Keys on the function env only (`sk_test_` / `pk_test_` / HMAC); nothing committed.

## Named deploy (codebase `tashil-mobile-notifications`)

Do **not** deploy `suspendExpiredSubscriptions` or blanket `functions`.

```bash
firebase deploy --project tashil-dev --only \
  functions:tashil-mobile-notifications:createSubscriptionCheckout,\
functions:tashil-mobile-notifications:paymobSubscriptionWebhook,\
functions:tashil-mobile-notifications:previewSubscriptionQuote,\
functions:tashil-mobile-notifications:reconcileSubscriptionPayments,\
functions:tashil-mobile-notifications:reconcileSubscriptionPaymentsScheduled,\
functions:tashil-mobile-notifications:expireAbandonedSubscriptionRenewals
```

After any deploy, confirm `GCLOUD_PROJECT` and other env vars on checkout/webhook
were not dropped (see `docs/SUBSCRIPTIONS.md` HOLDS / env notes).

## Behaviour (already on `dev`)

- One `delegate_requests` renewal per checkout; `coveredDelegateUids` + one Paymob charge.
- Server quotes via `previewSubscriptionQuote` / `quoteSubscriptionRequest`; client never sends amount.
- Scenarios matrix: `docs/PAYMOB_SCENARIOS.md`.
- UI: multi-select, filters, confirmation sheet, receipt, 100-delegate cap.

## Local verification

```bash
cd functions && npm test
flutter test test/features/admin/subscriptions/subscription_renewal_test.dart
node --test test/rules/subscriptions.test.js   # from repo root test/rules, via npm run test:rules:subs in CI
```