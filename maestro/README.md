# Maestro (tashil-dev black-box journeys)

Maestro covers **installed dev builds** (`com.tashil.delegate.dev`): login, navigation, profile/settings, logout, and session persist. **No native OS permission dialogs** — those live under `patrol_test/` (Patrol).

## Prerequisites

- Debug-dev build on device or simulator
- [Maestro CLI](https://maestro.mobile.dev/) on `PATH`
- Staff password from Project store (`internal/tashil-dev-test-accounts.txt`) — **never commit**

## User journeys (both login modes)

| Flow | Role segment | Accounts |
| --- | --- | --- |
| `flows/dev-staff-navigation-logout.yaml` | **موظف إداري** | Default phone `01500000002` |
| `flows/dev-delegate-navigation-logout.yaml` | **مندوب** | Phone `01500000003` + fake national ID (env) |
| `flows/dev-marketing-navigation-logout.yaml` | **التسويق** (`marketing`, TAS-393) | `TASHIL_MAESTRO_DEV_MARKETING_PHONE` (default `01000000007`) + `TASHIL_MAESTRO_DEV_MARKETING_SECRET`; skipped when the secret is unset. Tabs, search mode, logout |
| `flows/pr215-supervisor-identity-persist.yaml` | Staff + relaunch persist | Same as staff smoke |

```bash
export TASHIL_MAESTRO_DEV_SECRET='<from store>'
# optional: export MAESTRO_DEVICE_ID=<sim UDID>
bash maestro/run-dev-user-journeys.sh
```

Pass `-e` variables explicitly (some Maestro versions ignore shell export alone). See `maestro/env.example`.

## Semantics (ENV=dev only)

- `tashil_main_menu_button` — header menu
- `tashil_profile_phone_value` — profile phone row (staff flows)

Patrol integration tests reuse login helpers in `patrol_test/support/` for **setup only**; journey assertions stay in Maestro YAML here.
