# Backfill delegate holds (Phase 2 item 1)

Stamps `holds`, `source`, `rejectionReason` and `statusVersion` on nested
`delegates/{uid}` docs from the existing `status` / `statusReason` /
`delegateSource` fields. **Never writes `status` or `statusReason`.**

Dry-run is the default. Console output is counts only.

```
cd functions && npm run build
node scripts/backfill-delegate-holds.js --project tashil-dev
node scripts/backfill-delegate-holds.js --project tashil-dev --rollback ./delegate-holds-rollback.json
node scripts/backfill-delegate-holds.js --project tashil-dev --apply --rollback ./delegate-holds-rollback.json
node scripts/backfill-delegate-holds.js --project tashil-dev --revert --rollback ./delegate-holds-rollback.json
```

`--apply` against `practice-firebase-72df1` is refused unless a later written
go passes `--allow-prod-project=practice-firebase-72df1`.
