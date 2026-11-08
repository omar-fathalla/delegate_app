# Dev verification — tool roles (six-tool gate)

Scope: **`dev` / `tashil-dev` only**, fake accounts, ASCII digits in UI automation. Mac/simulator runs use the coordinator worker (`fathalla-mac`); Linux CI covers compile-time tools.

| # | Tool | What it covers | Typical command / location |
| --- | --- | --- | --- |
| 1 | **Dart / Flutter analyze** | Static types, lints, analyzer rules on `lib/` + `test/` | `flutter analyze --no-fatal-warnings --no-fatal-infos` (`.github/workflows/ci.yml`) |
| 2 | **Flutter test** | Widget/unit/integration Dart tests (incl. `test/patrol_test/*` helper contracts) | `flutter test --concurrency=1` |
| 3 | **Static checks** | Repo guard scripts (dev plist/Firebase, BGTask `offlineSyncTask`, Crashlytics strip, xctestrun helpers) | `bash scripts/ios_dev_config_check.sh`, `ios/scripts/test_offline_sync_bgtask_registration.sh`, `patrol_test/manifest/test_xctestrun_resolve.sh` |
| 4 | **APK build (dev)** | Produces installable **dev** artifact for emulator / device smoke | `flutter build apk --flavor dev --dart-define=ENV=dev` (coordinator gate; not CI on every PR by default) |
| 5 | **Maestro** | Black-box **user journeys** on installed dev app: **مندوب** + **موظف إداري** login, main navigation, profile/settings, logout; session persist (`maestro/flows/`, `maestro/run-dev-user-journeys.sh`). **No OS permission dialogs.** | `bash maestro/run-dev-user-journeys.sh` |
| 6 | **Patrol** | **Flutter + native** integration: OS permission dialogs, location/check-in, push/notification shade, `offlineSyncTask` post-launch window, background/foreground (`patrol_test/integration_*.dart`). Login helpers = setup only. | `patrol test -t patrol_test/integration_*.dart --flavor dev --dart-define=ENV=dev …` |

## Credentials

Staff password: Project store `internal/tashil-dev-test-accounts.txt` via env (`TASHIL_MAESTRO_DEV_SECRET`, `PATROL_DEV_SECRET`). Delegate national ID: public fake value in `docs/DEV_ENVIRONMENT.md` / `PATROL_DEV_NATIONAL_ID`.

## Policy

Batch local commits; **draft PR** while iterating; **one push** when ready; merge after **green CI** + Mac six-tool gate on merged `dev` SHA (coordinator).
