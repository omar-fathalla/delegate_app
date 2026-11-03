# Dev environment (tashil-dev) runbook

Prod is unchanged: `firebase deploy --only hosting` (default project
`practice-firebase-72df1`) still deploys to site `tashil-hr-test` through the
hosting target `web` in `.firebaserc`. The alias `dev` maps to `tashil-dev`,
where the same target points at site `tashil-dev`.

**Always pass `--project tashil-dev` (or `-P dev`) explicitly for dev work.**
Never deploy dev builds to `practice-firebase-72df1`.

## Storage bucket
No `bucket` override is needed: the CLI uses each project's default bucket
(`tashil-dev.firebasestorage.app` for dev, the existing bucket for prod).

## Preview channel deploy
```bash
flutter pub get
./scripts/build_web.sh dev        # ENV=dev build + dev Maps key in index.html
                                  # (script lands with the Maps key PR; until then:
                                  #  flutter build web --release --dart-define=ENV=dev)
firebase hosting:channel:deploy <channel> --project tashil-dev --expires 7d
```
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
