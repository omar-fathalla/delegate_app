# Firestore password fields on `users` documents

**Canonical plan (full analysis, rollout, and inventory):** Cursor Project store  
[`firestore-password-field-removal-plan.md`](https://cursor.com) — open **Tashil App → Context → `docs/firestore-password-field-removal-plan.md`**.

This repository copy is a **pointer only**. Do not duplicate the full runbook here.

**Quick facts**

- Secret field names: `password`, `temporaryPassword`, `tempPassword` on `users/{uid}`.
- Mobile staff login uses **Firebase Auth**, not Firestore passwords (see `lib/features/auth/data/datasources/auth_remote_data_source.dart`).
- Client writes of secret keys are **denied** in `firestore.rules`; legacy values may still be **readable** until Admin SDK purge (`functions/scripts/purge-password-fields.js`).
- Prod purge requires written approval; see `functions/scripts/README-p0-users-write.md`.