# Backfill `organizationUIDs` on existing `delegate_requests`

The add-delegate form can now put several chains on one request
(`organizationUIDs` / `organizationNames`). Older documents only have the
singular `organizationUID`. The app treats a missing list as
`[organizationUID]`, so it keeps working without this script. The script
exists so list queries and audit views see the same field on every doc.

## Usage (tashil-dev only)

Dry-run is the default. It always writes a rollback file first.

```
cd functions
node scripts/backfill-organization-uids.js --project tashil-dev \
  --rollback /tmp/organization-uids-rollback.json
```

Then apply, after the dry-run counts look right:

```
node scripts/backfill-organization-uids.js --project tashil-dev --apply \
  --rollback /tmp/organization-uids-rollback.json
```

The script sets `organizationUIDs = [organizationUID]` (and
`organizationNames = [organizationName]` when the name is present) on
documents that do not already have a non-empty list. It does not touch
prod, does not deploy functions, and prints counts only (no personal data).
