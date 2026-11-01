# Plaintext passwords in `users` — cleanup plan (PLAN ONLY)

Status: **plan only. Nothing has been written or deleted.** Needs Mohamed's approval before any step that touches production.

## What a read-only check found (2026-11-01, project practice-firebase-72df1)
Counts only. No values were read into logs or printed.

| | count |
|---|---|
| `users` docs total | 637 |
| docs with a password-like key | 112 |
| of those, with a non-empty value | 111 |
| keys | `password` ×112, `temporaryPassword` ×1 |
| test accounts among them | 0 |

Non-empty by role: marketing 69, marketing_promotion 22, branches_marketing 9, company-admin 6, organization-admin 1, super-admin 1, hr 1, accountant 1, technical_support 1.

Today `users` is readable by **anyone** (deployed rules: `allow read: if true`). Phase 1 and 1b change that to signed-in only, but anonymous sign-up is still open, so these values stay exposed until both the cleanup and the anonymous cut-over are done.

## Where the values come from (code)
- App `lib/features/admin/data/models/admin_user_model.dart` `toMap()` writes `'password': temporaryPassword` when staff are created from the app. `fromFirestore` reads it back, and the admin UI shows it.
- App `lib/features/profile/presentation/pages/user_profile_screen.dart:1084` writes the new password into the users doc on a password change.
- Legacy company-admins were created by super-admin with the password stored.

## Steps (each needs approval)
1. **Stop new writes (code, one PR):** remove `password` from `AdminUserModel.toMap()` and from the profile password change. Show the temporary password once at creation, not from Firestore. Release with the next app version.
2. **Rotate first, then delete.** Every one of the 111 passwords should be treated as leaked. Force a reset (Auth `updateUser` with a random password + send a reset link, or require a change at next login) for the affected accounts, starting with super-admin, technical_support, organization-admin and company-admin.
3. **Delete the fields:** an Admin SDK script with `--dry-run` (default, prints counts only) and `--apply`. It uses `FieldValue.delete()` on `password` and `temporaryPassword` in batches of 400, and logs doc IDs only. It writes a backup of affected doc IDs (no values) to a local file.
4. **Verify:** re-run the read-only count. It must be 0.
5. **Close the read:** deploy the Phase 1 rules (users: signed-in only), then disable anonymous auth (see ANONYMOUS_AUTH_CUTOVER.md).

## Rollback
Step 3 is not reversible by design; the values must not be kept. Step 2 is the safety net: accounts get new passwords before the old ones are removed.

## Open decisions
- Force reset for all 111, or only privileged roles first?
- How should staff get the new passwords: reset email, or the admin shares a temporary one?
