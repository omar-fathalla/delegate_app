# Local testing against the Firebase emulators (no production access)

Everything runs on the Mac against the emulators with project `demo-tashil-local`. A `demo-*` project cannot reach production. The data is fake.

## 1. Rules unit tests (fast, ~10 s)
```bash
cd rules-tests && npm install && npm test        # phase 1 + phase 1b suites
```

## 2. Start the emulators + seed fake data
```bash
scripts/local_rules_test.sh                 # rules = firestore.rules.phase1b (default)
RULES=phase1   scripts/local_rules_test.sh  # compare: phase 1 rules
RULES=deployed scripts/local_rules_test.sh  # compare: current production rules
```
This starts Auth 9099, Firestore 8080, Functions 5001 (incl. `delegateLoginV2`, `staffPhoneLookup`), Storage 9199 and the UI on http://127.0.0.1:4000. Then it seeds the accounts below and keeps running until Ctrl+C.

Backend smoke test (logs in like the app and runs the scoped queries), in a second terminal:
```bash
cd scripts/local && node smoke.mjs
```

## 3. Run the app against the emulators
```bash
flutter run -d chrome --dart-define=USE_FIREBASE_EMULATOR=true     # web (staff / HR portal)
flutter run -d macos  --dart-define=USE_FIREBASE_EMULATOR=true
open -a Simulator && flutter run -d "iPhone 16" --dart-define=USE_FIREBASE_EMULATOR=true   # delegate login
# Android emulator: add --dart-define=EMULATOR_HOST=10.0.2.2
```
The flag is off by default, so normal and release builds are unchanged. With the flag on, the app prints `*** USING FIREBASE EMULATORS ***` and uses project `demo-tashil-local`.
Rule denials appear in the app logs as `permission-denied` and in Emulator UI → Firestore → Requests.

## Seeded accounts (FAKE, emulator only)
Staff: log in with phone + password `Test@12345`.

| Role | Phone | Org | Company |
|---|---|---|---|
| super-admin | 01090000001 | – | – |
| technical_support | 01090000002 | org_test_a | – |
| organization-admin | 01090000003 | org_test_a | – |
| marketing | 01090000004 | org_test_a | – |
| marketing_promotion | 01090000005 | org_test_a | – |
| branches_marketing | 01090000006 | org_test_a | – |
| accountant | 01090000007 | org_test_a | – |
| company-admin (supervisor) | 01090000008 | org_test_a | co_test_a1 |
| company-admin without company | 01090000009 | org_test_a | – |
| company_supervisor | 01090000010 | org_test_a | co_test_a1 |
| hr | 01090000011 | org_test_a | co_test_a1 |
| organization-admin (other org) | 01090000012 | org_test_b | – |

Delegates: log in with phone + national ID (mobile app).

| Phone | National ID | Company |
|---|---|---|
| 01080000001 | 29901010100011 | co_test_a1 (delegate) |
| 01080000002 | 29901010100022 | co_test_a1 (position supervisor) |
| 01080000003 | 29901010100033 | co_test_a2 |
| 01080000004 | 29901010100044 | co_test_b1 (other org) |

## What to check per role
- The home screen and the delegates lists open with no `permission-denied`.
- Org staff see only org_test_a delegates; the org B admin sees only co_test_b1.
- Company staff see their company / org, never org B.
- A delegate can log in, see their profile and their company supervisor, and cannot see other companies.

## Notes
- The script patches the *build output* `functions/lib` so that `admin.firestore.Timestamp/FieldValue` work inside the Functions emulator. The source is unchanged.
- Remote Config / Installations calls get 403 with the demo project; the app falls back to defaults (OTP flag off).
