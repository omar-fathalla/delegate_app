# Staff JWT `phones` claim backfill

One-time mint of `phones: phoneQueryVariants(normalizePhone(users.phoneNumber))` on Firebase Auth **staff** accounts so TA-60 bell rules can match JWT-only phone tags.

Ongoing updates are handled by **`onStaffUserPhonesClaimSync`** (Firestore `users/{uid}` write trigger).

## Collision check

A staff user gets no `phones` claim (and any existing one is cleared) when the
same phone, after `normalizePhone`, sits in any of `phoneNumber`, `phone`,
`mobile` or `mobileNumber` on another `users` doc or on any `delegates` doc.
The script builds that index with one full scan (phone fields only), so values
stored as `+20 105 550 0003`, `0020…`, Arabic digits or numbers all count.
When the Auth user has a `phoneNumber`, that verified phone is minted instead
of the client-writable `users.phoneNumber`.

## Safety

- **Dry-run is the default** (omit `--apply`, or pass `--dry-run`). Counts only; no Auth writes.
- **`--project` is required** (no default).
- **tashil-dev first**, then production **only after Mohamed approval**.
- Prod project `practice-firebase-72df1` requires `--allow-prod-project=practice-firebase-72df1`.
- This script does **not** deploy Cloud Functions.

## Order (rollout)

1. Deploy `onStaffUserPhonesClaimSync` to the target project (isolated codebase `tashil-mobile-notifications`).
2. Run this backfill (`--dry-run`, then `--apply` on tashil-dev).
3. Wait ~1 hour (or force token refresh) so clients pick up new claims.
4. Deploy Firestore rules (TA-60 staff bell JWT matcher).

## Examples

```bash
cd functions
node scripts/backfill-staff-phones-claim.js --project tashil-dev --dry-run
node scripts/backfill-staff-phones-claim.js --project tashil-dev --apply
```

Prod (Mohamed only, after written go):

```bash
node scripts/backfill-staff-phones-claim.js \
  --project practice-firebase-72df1 \
  --allow-prod-project=practice-firebase-72df1 \
  --dry-run
```