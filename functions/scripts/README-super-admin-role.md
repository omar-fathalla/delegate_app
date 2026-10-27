# Optional super-admin role migration

The app writes `super-admin`. `isSuperAdmin()` also accepts the legacy spellings `super_admin`, `superadmin`, and `superAdmin` until this script is applied. A client write of those legacy spellings is rejected. Documents that still store `super_admin` keep super-admin access, and this script rewrites them to `super-admin`.

Do not run this as part of deploy. `functions/scripts/migrate-super-admin-role.js` is not imported by `index.ts`.

## What it does

1. Query `users` where `role == "super_admin"`.
2. Query `collectionGroup('delegates')` where `role == "super_admin"`.
3. Set those `role` fields to `super-admin`. Leave every other field, and every other role spelling, unchanged.
4. Print document paths and two counts. It does not print document bodies.

The query is exact, so `super-admin`, `superAdmin`, and `superadmin` are not rewritten. Re-running after a successful apply updates nothing.

## How to run

From `functions/`, with Application Default Credentials for the Firebase project:

```bash
node scripts/migrate-super-admin-role.js
node scripts/migrate-super-admin-role.js --apply
```

The first command is a dry run. `--apply` is the only flag that writes. Running it against production is a separate, reviewed operation.
