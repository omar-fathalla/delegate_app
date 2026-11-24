# Dev environment (tashil-dev) runbook

Prod is unchanged: `firebase deploy --only hosting` (default project
`practice-firebase-72df1`) still deploys to site `tashil-hr-test` through the
hosting target `web` in `.firebaserc`. The alias `dev` maps to `tashil-dev`,
where the same target points at site `tashil-dev`.

**Always pass `--project tashil-dev` (or `-P dev`) explicitly for dev work.**
Never deploy dev builds to `practice-firebase-72df1`.

## Warm the CDN after every web deploy (TAS-200)
Right after a Hosting deploy the CDN is empty and the first visitor waits
25-48 s for `main.dart.js` from the origin. Run this right after the deploy,
from the same checkout (it also requests every big file in `build/web`):
```bash
bash scripts/warm_web_cdn.sh https://tashil-dev.web.app     # dev
bash scripts/warm_web_cdn.sh https://hr.sw-point.com        # prod, after the prod deploy
```
It only warms the edge nearest to the machine that runs it.

## Storage bucket
No `bucket` override is needed: the CLI uses each project's default bucket
(`tashil-dev.firebasestorage.app` for dev, the existing bucket for prod).

## Preview channel deploy
```bash
flutter pub get
./scripts/build_web.sh dev        # ENV=dev build + dev Maps key in index.html
firebase hosting:channel:deploy <channel> --project tashil-dev --expires 7d
```
ALWAYS build dev web with `scripts/build_web.sh dev`. A plain
`flutter build web --dart-define=ENV=dev` leaves the prod Maps key in
`index.html`. The script fails if any prod Maps/Places key remains in
`build/web` or the dev Maps key is missing from `index.html`.
Note: a `--dart-define=MAPS_API_KEY=...` override only changes the Dart side;
it does NOT change the key in `index.html`.
Rules / indexes / functions (dev only):
```bash
firebase deploy --only firestore:rules,firestore:indexes,storage --project tashil-dev
(cd functions && npm ci && npm run build)   # no predeploy hook
firebase deploy --only functions:tashil-mobile-notifications:<fn> --project tashil-dev
```

## Referrer step (required for every new preview host)
API key referrer wildcards such as `tashil-dev--*.web.app/*` do **not** match
preview hosts. After the first deploy of a channel, add its exact host
(e.g. `tashil-dev--<channel>-<hash>.web.app/*`) to BOTH dev keys:

- "Browser key (auto created by Firebase)" (Firebase web key)
- "Dev Maps/Places web key" (Maps JavaScript API + Places API)

`gcloud services api-keys update` **replaces** restrictions, so always pass the
full referrer list and every API target in one call. For the Browser key that
means re-passing all its Firebase API targets
(`gcloud services api-keys describe <KEY_ID> --project tashil-dev` first).

### zsh note
In zsh, flags stored in a string variable are not word-split. Use an array:
```zsh
T=(); for s in identitytoolkit.googleapis.com securetoken.googleapis.com; do T+=(--api-target=service=$s); done
R="localhost:*,127.0.0.1:*,tashil-dev.web.app/*,tashil-dev.firebaseapp.com/*,tashil-dev--<channel>-<hash>.web.app/*"
gcloud services api-keys update <KEY_ID> --project tashil-dev --allowed-referrers="$R" "${T[@]}"
```

## Fake test accounts (tashil-dev only, fictional data)
| Role | Phone | Login |
|---|---|---|
| super-admin | 01500000001 | phone + password |
| supervisor (`supervisor`) | 01500000002 | phone + password |
| delegate | 01500000003 | phone + fake national ID |

Auth test phone numbers +201500000003 / +971500000001 use a fixed code.
Passwords and codes are **not** in the repo; they are kept in the operator's
creds file (`/workspace/tashil-dev-test-accounts.txt`, chmod 600, on the
agent box). Log in at most once per account per smoke run (lockout).

### Delegates and device binding (TAS-228)
A delegate is bound to the first device that logs in. Any other device then
stops at «الحساب مقترن بجهاز آخر». So each device type gets its own account:

| Use | Account | Phone | Fake national ID |
|---|---|---|---|
| Real Android device (M31) | shared dev delegate | 01500000003 | 29901015740919 |
| Local Mac gate (Maestro, Patrol) | seed `alpha` delegates | set in `~/.tashil-ci.env` | — |
| Manual emulator / simulator, delegate | seed `beta-1` (Promoter) | 01000000018 | 00000000000201 |
| Manual emulator / simulator, supervisor | seed `beta-4` (Supervisor) | 01000000021 | 00000000000204 |

- Seed delegates come from `functions/scripts/hr-web-fake-accounts.js`. In
  each fake company, delegates 1-3 are Promoters, 4 is a Supervisor and 5 is
  suspended. The national ID is `0000000000` + company code (`01` alpha,
  `02` beta) + the two-digit index (`fakeNationalId`).
- Free every seed delegate's device binding (tashil-dev only). The Mac gate
  runs this before each device step:
  ```bash
  cd functions && node scripts/hr-web-fake-accounts.js --project tashil-dev --reset-device-bindings --apply
  ```
- Keep 01500000003 for the M31. If you log it in somewhere else, the M31
  needs its binding cleared before it can log in again.
