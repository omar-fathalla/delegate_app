# P0 users-write scripts

Not deployed, not imported by index.js. Each needs `--project`, refuses the
prod project, and defaults to a dry run that prints counts only (never paths,
emails, passwords or links). **Do not run on prod without written approval.**

| Script | Dry run | `--apply` |
|---|---|---|
| `purge-password-fields.js` | counts docs with `password` / `temporaryPassword` / `tempPassword` | deletes those fields |
| `revoke-and-force-reset.js` | counts staff targets (super-admins first; `--super-only`) | revokes refresh tokens, sets `requireReLogin`, queues a reset email via `mail` |
| `role-counts.js` | per-role counts (reads `role` only) | not supported |

Order on approval: deploy PR (b) functions and ship PR (c) app first, then
purge (dry run → apply), then revoke+reset `--super-only`, then all staff.
Delegates/promoters are never touched.

Test: `npm run test:p0-scripts` (root; Auth + Firestore emulators).
