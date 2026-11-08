# Mac six-tool preflight

Run on **`fathalla-mac`** before Maestro / Patrol / screenshot attestation. Linux CI does **not** execute device steps; it runs the static guards wired in `.github/workflows/ci.yml`.

## Script

```bash
bash scripts/mac_gate_preflight.sh
```

| Env | Purpose |
| --- | --- |
| `TASHIL_SIM_UDID` | Default `8CD21E86-592A-4ED5-9F41-BF90CB9796C6` (iPhone 17) |
| `TASHIL_PROJECT_STORE` | Default `/cursor/stores/bc-10199080-bfc7-439b-bdd9-fe57400f78e2` |
| `TASHIL_PROJECT_STORE_MEDIA` | Override screenshot directory (default `$TASHIL_PROJECT_STORE/media`) |
| `TASHIL_PREFLIGHT_KEEP_BOOT=1` | Skip `simctl shutdown` on exit |

## What it checks

1. **Worker / connectivity hints** — echoes `fathalla-mac`, toolchain versions, and Project store paths (same layout as coordinator attestation docs).
2. **Simulator boot** — boots the pinned UDID if not already booted.
3. **Tashil Dev installed** — `com.tashil.delegate.dev` via `simctl get_app_container`.
4. **Login screenshot** — terminates + launches dev app, captures `media/dev-login-roles-<git-short>.png` under the Project store. Verify the image shows **مندوب / موظف إداري** (app foreground), not SpringBoard home.
5. **Shutdown** — `simctl shutdown` on exit unless `TASHIL_PREFLIGHT_KEEP_BOOT=1` (per project preference: boot when needed, shut down when finished).

## After preflight

| Step | Command |
| --- | --- |
| Maestro journeys | `bash maestro/run-dev-user-journeys.sh` |
| Patrol integration | `bash scripts/patrol_run_dev_integration.sh` |
| Full matrix | [tool-roles.md](./tool-roles.md) |
