# startBillingCycle (Phase 2 item 2)

Server replacement for the web W7 button (`clearAllDeferredPayments$` in
`company.service.ts`, triggered from `org-financial-details.ts`). This
repository does not change the web app. The contract below is for the web
team to call, then hide or remove the old client-side fleet write.

Deploy (tashil-dev only, named function):

```
npx firebase-tools@14.15.1 deploy \
  --only functions:tashil-mobile-notifications:startBillingCycle \
  --project tashil-dev
```

Do not deploy `suspendExpiredSubscriptions` with this function. The web
repo stays read-only.

## Callable

- Name: `startBillingCycle`
- Region: `us-central1`
- Auth: signed-in org admin of `orgId`, or a super admin. Company admins
  are refused. An org admin with an empty `organizationUID` is fail-closed.
- App Check is not enforced (Flutter does not ship it yet), same as
  `setDelegateHold`.

Request:

```
{ orgId: string, cycleId: string }
```

`cycleId` is the idempotency key for this org (recommended: the period
code, e.g. `2027_H1`). Allowed characters: letters, digits, `.`, `_`, `-`.
`organizationUID` is accepted as an alias of `orgId`.

Response:

```
{
  ok: true,
  state: "running" | "done",
  resumed: boolean,
  unchanged: boolean,      // already done for this org+cycleId
  inProgress?: boolean,    // another caller holds the lease
  orgId, cycleId, periodCode, mode,
  counts: {
    docs, companies, companiesReset, written, skipped,
    byReason: { source_app?, app_added_request?, paid_subscription?, ... }
  }
}
```

If `state` is `running` and `inProgress` is not set, call again with the
same `{orgId, cycleId}` until `state` is `done`. A repeat call after
`done` is a no-op (`unchanged: true`) and returns the stored counts.

Run document (server-only): `billing_cycles/{orgId}_{cycleId}`
(`running|done`, cursor, counts). Clients cannot read or write it.

## Behaviour

- In **authoritative** mode only, resets every company under the org:
  `deferredPayment=0`, `hasDeferredPayment=false`,
  `totalApprovedDelegates=0`, and sets `isPrinted` to `false` on held
  delegates. Previous values are stored on the `billing_cycles` run doc
  (`companyPriors`, `delegatePriors`) so they can be restored.
- Adds a `billing_cycle_reset` hold on **web-billed** chain docs in that
  org. Scope is per org (every chain of the uid in that org).
- In shadow mode (the default until Phase 2 item 4) it writes only to
  `billing_cycles` or shadow fields (`holds`, `statusHistory`, priors).
  It does **not** write `status`, `statusReason`, company billing
  counters, or `isPrinted`.
- Skips a doc when any of these is true:
  - `source` / `delegateSource` is `app`
  - the uid is an approved app `new_delegate` request (same rule as
    `isAppAddedRegistration` / `appAddedDelegateUids`)
  - `subscription.paymentStatus` is `paid` or `waived` for the current
    period, or a paid/waived request already covers the uid for that period
  - status is `pending`, `rejected`, or already `suspended`
  - the hold is already present
- Legacy `approved` is treated as active and is included.
- Batch size is 200 documents (up to 400 writes with history). The run is
  resumable if the callable hits its time budget.

Reactivation of `billing_cycle_reset` (and the server-side fee) stays on
`setDelegateHold` / later writers. This callable only starts the cycle.

Until the web switches to this callable, the old W7 button must stay
behind a flag or unused on tashil-dev.
