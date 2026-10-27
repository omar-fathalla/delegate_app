# Backfill check_in denormalized fields

Stamps `delegateName`, `phoneNumber`, `companyName`, `personalPhotoURL`, and
checkout fields (`checkOutTime`, `checkOutDocId`, `checkOutLocation`) onto
`attendance_logs` documents of `type=check_in`.

**Default is dry-run.** Test only against the Firestore emulator.

```bash
cd functions
firebase emulators:exec --only firestore \
  "node scripts/backfill-checkin-denorm.emulator.test.js"
```

Dry-run against emulator with a date/org filter:

```bash
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 \
  node scripts/backfill-checkin-denorm.js \
    --org <ORG_ID> --from 2026-10-01 --to 2026-10-28
```

Do **not** run `--apply` against production from this workflow.
