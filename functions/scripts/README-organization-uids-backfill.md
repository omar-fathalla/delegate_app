# Backfill `organizationUIDs` on existing `delegate_requests`

The add-delegate form can now put several chains on one request
(`organizationUIDs` / `organizationNames`). Older documents only have the
singular `organizationUID`. The app treats a missing list as
`[organizationUID]`, so it keeps working without this script. The script
exists so list queries and audit views see the same field on every doc.

## Safety

- **Target:** `tashil-dev` only. `practice-firebase-72df1` (prod) is refused
  unless a later written go passes `--allow-prod-project=` with approval from
  **Mohamed Fathallah** (required approver for any production run; not approved
  for this backfill today).
- **Default mode is dry-run** (no writes). Pass `--apply` to write.
- **`--dry-run`** may be passed explicitly (same as omitting `--apply`).
- Never combine `--dry-run` with `--apply`.
- **`--rollback` paths:** each run (dry-run or apply) must use a **new**
  rollback file path. If the path already exists on disk, the script **refuses
  to start** instead of overwriting a prior run’s rollback JSON.
- **Apply guard:** `--apply` re-reads each planned document before write and
  skips docs that changed since the scan (same idea as restore
  compare-before-write).
- Prints counts only in stdout (no personal data in logs).
- Does not deploy functions or rules.

## Run order for Mohamed (tashil-dev only, never prod)

Run from a clean checkout at the merge commit SHA printed in the PR (after CI
is green). Record that SHA in your ops log before any live run.

```bash
cd /path/to/delegate_app
git fetch origin dev
git checkout <MERGE_SHA>   # full SHA from the PR merge commit
cd functions
npm ci
```

Authenticate to GCP/Firebase Admin for **tashil-dev** (your usual
`gcloud auth application-default login` or service account).

### 1 — Dry-run first (required)

Writes a rollback JSON and a report under `/tmp`; **no Firestore writes**.
Use a dedicated rollback path for this run only.

```bash
node scripts/backfill-organization-uids.js \
  --project tashil-dev \
  --dry-run \
  --rollback /tmp/organization-uids-rollback-dryrun-<runId>.json
```

Review `planned` vs `skipped` in the printed counts and the report file
(`organization-uids-report-*.json`, unique suffix per run). Confirm the rollback
file lists only `delegate_requests/*` paths you expect.

### 2 — Apply on tashil-dev only (after dry-run sign-off)

**Do not reuse the step 1 rollback path.** Choose a **new** `--rollback` path;
apply writes a fresh rollback snapshot for that run, then writes Firestore.

```bash
node scripts/backfill-organization-uids.js \
  --project tashil-dev \
  --apply \
  --rollback /tmp/organization-uids-rollback-apply-<runId>.json
```

The script sets `organizationUIDs = [organizationUID]` (and
`organizationNames = [organizationName]` when the name is present) on
documents that do not already have a non-empty list. Check `applySkipped` /
`applySkipReasons` in the report if any doc changed between scan and apply.

### 3 — Rollback (optional)

Use the rollback file from the **apply** run (not the dry-run file). Dry-run
restore (compare-before-write; skips docs changed after the backfill):

```bash
node scripts/backfill-organization-uids.js \
  --project tashil-dev \
  --dry-run \
  --restore /tmp/organization-uids-rollback-apply-<runId>.json
```

Apply restore only if the dry-run restore counts look right:

```bash
node scripts/backfill-organization-uids.js \
  --project tashil-dev \
  --apply \
  --restore /tmp/organization-uids-rollback-apply-<runId>.json
```

## Related app work

Multi-chain request flows (picker, one fee, batch approval) are documented in
`docs/SUBSCRIPTIONS.md` § Multi-chain new-delegate requests. No extra app
deploy is required for this backfill alone; run the script when tashil-dev
should show `organizationUIDs` on legacy `delegate_requests`.