# Prod-only staff password callables (recovery blocker)

These functions are deployed on `practice-firebase-72df1` but are **not** in this repository:

- `completeStaffPasswordSetup`
- `requestStaffPasswordReset`
- `sendStaffPasswordSetupEmail`

## Recovery steps (Mohamed / Engineering)

```bash
gcloud functions describe completeStaffPasswordSetup \
  --project=practice-firebase-72df1 --region=us-central1
# Download source from the returned sourceArchiveUrl or Cloud Console → function → Source.

firebase functions:config:get --project=practice-firebase-72df1  # if legacy config used
```

Add recovered TypeScript under `functions/src/`, export from `functions/src/index.ts`, and add emulator/e2e tests before any targeted deploy.

## Why Phase 0 did not add stubs

A stub export that does not match prod behavior would break the web staff password flow. This agent environment had **no** Firebase login and the in-repo Play Console service account lacks `cloudfunctions.functions.get` on prod (403).

Do **not** run `firebase deploy --only functions:tashil-mobile-notifications` without these three exports until source is merged.
