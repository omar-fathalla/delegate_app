# Designated TEST accounts (local reference)

These accounts exist only for engineering/perf/UI verification against
`practice-firebase-72df1`. They are **not** production operators.

Do **not** store passwords in this file.

## probe.tashil.test1@gmail.com

| Field | Value |
| --- | --- |
| Email | `probe.tashil.test1@gmail.com` |
| Auth UID | `O0LHjrZU7TXG5LHi9QcqavE4i1q1` |
| Firestore doc | `users/O0LHjrZU7TXG5LHi9QcqavE4i1q1` (doc id **must** equal Auth UID for rules) |
| Purpose | Designated **TEST** account for app/perf checks |
| Default role | `branches_marketing` (switchable per test stage; not a production user) |
| Display name | `TEST Branch Marketing` |
| Phone (synthetic) | `01555550001` |
| Organization | `PiioBFgxaHAeuRdjlDgj` |
| Linked branch (doc metadata) | `Smoha` (top live-attendance branch on 2026-10-27 Africa/Cairo) |
| Favorites | On-device SharedPreferences only (`marketing_fav_branches_<uid>`). Not Auth password. |
| Auth password | Unknown — **do not reset** for automated runs; prefer Admin custom-token sign-in |
| Custom claims | Not required for staff (rules use `users/{auth.uid}.role`) |

### How to sign in for automation

1. Mint a Firebase custom token for the Auth UID (service account with sign capability).
2. Client `signInWithCustomToken`, then rely on auto-login cache **or** use
   `lib/main_real_test.dart` with `--dart-define=REAL_TEST_CUSTOM_TOKEN=...`.
3. UI email/password login needs the Auth password; if unknown, do not reset —
   use the custom-token path instead.

### Role switching

For a later test stage, update only this users doc's `role` (and keep
`testAccount: true`). Do not reuse real staff accounts.
