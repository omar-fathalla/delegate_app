# Patrol (Flutter + native integration)

Patrol covers **OS dialogs**, **location / check-in**, **push notification UI**, **`offlineSyncTask` timing**, and **background/foreground** on dev flavor builds. **Black-box login journeys** (both roles, nav, logout) are **Maestro-only** — see `maestro/README.md`.

Login helpers under `patrol_test/support/` are **setup only** (`patrol_dev_session.dart`, `submitDevDummyLogin`, `submitDevDelegateDummyLogin`). Do not assert profile/role journeys here.

## Command (Mac / emulator)

```bash
export PATROL_DEV_SECRET='<from Project store internal/tashil-dev-test-accounts.txt>'

patrol test \
  -t patrol_test/integration_native_permissions_test.dart \
  -t patrol_test/integration_location_checkin_test.dart \
  -t patrol_test/integration_push_notification_test.dart \
  -t patrol_test/integration_offline_sync_lifecycle_test.dart \
  --flavor dev \
  --dart-define=ENV=dev \
  --dart-define=PATROL_DEV_SECRET="$PATROL_DEV_SECRET"
```

Delegate tests default `PATROL_DEV_PHONE=01500000003` when you pass `--dart-define=PATROL_DEV_PHONE=01500000003` for location files only, or run `-t` per file with role-specific defines.

## Split vs Maestro

| Concern | Tool |
| --- | --- |
| Login both roles, menu, profile/settings, logout | Maestro `maestro/flows/dev-*-navigation-logout.yaml` |
| Location / notification / camera OS prompts | Patrol `integration_native_permissions_test.dart` |
| Live tracking / check-in path | Patrol `integration_location_checkin_test.dart` |
| Notification shade / FCM handling | Patrol `integration_push_notification_test.dart` |
| `offlineSyncTask` delay + app background/foreground | Patrol `integration_offline_sync_lifecycle_test.dart` |
| Marketing floor check written under live rules + survives background (TAS-393) | Patrol `integration_marketing_floor_check_test.dart` (`PATROL_DEV_MARKETING_SECRET`, skipped without it; data from `functions/scripts/seed-marketing-journey-data.js`) |

## iOS notes

Same arm64 sim pin and frozen manifest workflow as before; see `patrol_test/manifest/README.md`.
