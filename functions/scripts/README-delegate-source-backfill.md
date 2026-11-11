# Backfill `delegateSource` (Phase 1 item 1)

Stamps `delegateSource`, `chainOrigin`, `delegateSourceInferredBy`,
`delegateSourceAt`, and `delegateSourceRunId` on nested
`organizations/{org}/companies/{company}/delegates/{uid}` docs that do
not already have `delegateSource`. Inference follows
`DELEGATE_SUBSCRIPTION_PHASE1_PLAN.md` §5.4.

Clients cannot set or change these fields (Firestore rules). The
`stampDelegateSource` function (Admin SDK) fills them on new docs.
This script backfills existing docs.

## Safety

- Dry-run by default (no writes).
- `--project` is required. Allow-list is `tashil-dev` (and `demo-*` for
  emulators). `practice-firebase-72df1` is refused unless a later,
  explicit written go passes `--allow-prod-project=practice-firebase-72df1`.
- Reports may include document paths and uids only — never names, phones,
  or national IDs.

## Usage

```bash
cd functions
npm run build
# Dry-run (default) and save the rollback file *before* any writes
node scripts/backfill-delegate-source.js --project tashil-dev \
  --report /tmp/delegate-source-report.json \
  --rollback /tmp/delegate-source-rollback.json

# Apply (tashil-dev only) after the rollback file exists
node scripts/backfill-delegate-source.js --project tashil-dev --apply \
  --report /tmp/delegate-source-report.json \
  --rollback /tmp/delegate-source-rollback.json

# Revert a run
node scripts/backfill-delegate-source.js --project tashil-dev --revert --run <runId> --apply
# or
node scripts/backfill-delegate-source.js --project tashil-dev --revert --rollback /tmp/delegate-source-rollback.json --apply
```

`--revert` without `--apply` is a revert dry-run.

## Web `requests` lookup

The script first tries a collection-group query on `requests`
(`actionType` + `targetDelegateId`). That composite index is not
required for this PR and is not created automatically. If the query
fails, it falls back to
`organizations/{org}/companies/{company}/requests` for each company
already seen on a delegate doc (single-field `actionType`, filtered in
memory). The report records `webQueryOk` and `webQueryMode`.

## Review docs (safest rule)

Inference follows plan §5.4. Docs with **no app or web evidence** are
rule 5: `delegateSource: 'web'`, `chainOrigin: 'unknown'`, confidence
`review`. That is the safest default — **keep them `web` unless the
evidence says app**.

Evidence that says app:

- Rule 1 or 2 (an app `delegate_requests/{uid}` new_delegate with a
  supervisor) — high confidence `app`
- Rule 4 (`registeredVia == 'mobile_app'` and no web/app-request
  signals) — low confidence `app`, listed in `lowConfidenceUids`

A tashil-dev dry-run (runId `dev-20261110T224032Z-b4c1ea`, nested
web-request fallback) found 104 unstamped docs: 4 rule-1 `app` (high)
and 100 rule-5 `web` (review). Zero rule 4. The 100 review docs stay
`web`.
