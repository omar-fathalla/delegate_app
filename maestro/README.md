# Maestro (iOS dev flavor)

Manual **tashil-dev** UI flows for PR #215 User Test. **No secrets in this tree.**

## Prerequisites

- Debug-dev sim build installed: `com.tashil.delegate.dev`
- [Maestro CLI](https://maestro.mobile.dev/) on `PATH`
- Dev test credentials from the coordinator Project store (`internal/tashil-dev-test-accounts.txt`) — **never commit or paste passwords**

## Supervisor identity + persist

Matches Mac flow `maestro-pr215-supervisor-identity-persist-9fd9d0d` (see `internal/pr215-hold-9fd9d0d-consolidated-user-test-attestation.md`).

```bash
export TASHIL_MAESTRO_DEV_PHONE=01500000002
export TASHIL_MAESTRO_DEV_SECRET='<from store doc only>'
# optional: export MAESTRO_DEVICE_ID=<sim UDID>

bash maestro/run-pr215-supervisor-identity-persist.sh
```

The runner passes Maestro `-e TASHIL_MAESTRO_DEV_PHONE=…` and `-e TASHIL_MAESTRO_DEV_SECRET=…` so flow `${…}` substitution works (export alone is not enough on some Maestro versions).

Direct CLI (equivalent):

```bash
maestro test -e TASHIL_MAESTRO_DEV_PHONE=01500000002 \
  -e TASHIL_MAESTRO_DEV_SECRET='<from store>' \
  maestro/flows/pr215-supervisor-identity-persist.yaml
```

See `maestro/env.example` for variable names only (no secrets in repo).

Environment:

| Variable | Required | Notes |
|----------|----------|--------|
| `TASHIL_MAESTRO_DEV_SECRET` | yes | Staff password / national ID for the dev account (second login field) |
| `TASHIL_MAESTRO_DEV_PHONE` | no | Defaults to `01500000002` |
| `MAESTRO_DEVICE_ID` | no | Passed to `maestro test --device` |
| `TASHIL_MAESTRO_LOG` | no | Default `maestro/logs/supervisor-identity-persist.log` (gitignored) |

M3 login (supervisor flow): tap segment **موظف إداري**, fill **رقم الجوال** + **كلمة المرور**, submit **تسجيل الدخول** (`ValueKey('login_submit')` in app). Delegate smoke uses segment **مندوب** + national ID field instead.

Semantics ids (ENV=dev only): `tashil_main_menu_button`, `tashil_profile_phone_value`.
