# Optional delegate auth backfill

Phase 1 does **not** need a backfill before `delegateLoginV2` is deployed or before delegates sign in.

`createCustomToken` uses the primary delegate document id as the Firebase Auth uid. The Auth user is created on the first `signInWithCustomToken`. The mobile app keeps using that Firestore document id as `Delegate.uid`, which is the same id it already stored for attendance, device binding, and notifications. Existing phone formats and national-ID field names are normalized at read time.

## When a backfill would matter

Only a later rules phase needs it, and only for a person who has **more than one** delegate document (more than one company or organization). The custom token uid is a single primary document id. The other documents stay under their own ids and are listed in the `delegateIds` custom claim. Rules can allow those documents with the claim. A stored `authUid` field is only useful if a rule must compare `request.auth.uid` to every document without reading the claim.

## What the script would do

Do not run this as part of deploy. It is a one-off Admin SDK job, dry-run unless an operator passes an explicit apply flag.

1. Read `collectionGroup('delegates')`. Do not change document ids. Do not delete documents.
2. Normalize each `phoneNumber` / `phone` the same way `delegateLoginV2` does, and read the national ID from `nationalityID`, `nationalityId`, `nationalId`, `nationalID`, `national_id`, or `idNumber`.
3. Group documents that share the same normalized phone and normalized national ID.
4. Pick the primary document: status not in `pending`, `suspended`, `rejected`, `blocked`, `inactive`, `disabled`, `banned`; then earliest `createdAt`; then the smallest document id. That id is the Auth uid the function already mints.
5. On every document in the group, set `authUid` to that primary id. Leave `phoneNumber` as-is unless a separate normalize pass is requested. A normalize pass would write the canonical `01xxxxxxxxx` value and is still optional, because login queries the known variants.
6. Print counts only: groups, documents updated, documents skipped because they have no phone or national ID. Never print national IDs, phone numbers, or tokens.
7. Re-run safely. Writing the same `authUid` again is a no-op.

No script is wired into `index.ts` or `npm run deploy`. Running it against production is a separate, reviewed operation.
