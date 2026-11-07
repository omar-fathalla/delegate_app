# Patrol iOS dev smoke (PR #218)

## Command (Mac)

Use a **concrete simulator UDID** so the run phase targets the right device (Mohamed default: iPhone 17 `8CD21E86-592A-4ED5-9F41-BF90CB9796C6`):

```bash
export PATROL_DEV_SECRET='<from Project store internal/tashil-dev-test-accounts.txt>'

patrol test \
  -t patrol_test/smoke_dev_login_test.dart \
  --flavor dev \
  --dart-define=ENV=dev \
  --dart-define=PATROL_DEV_SECRET="$PATROL_DEV_SECRET" \
  -d 8CD21E86-592A-4ED5-9F41-BF90CB9796C6
```

Optional: `--dart-define=PATROL_DEV_PHONE=01500000002` (default staff supervisor), `--dart-define=PATROL_DEV_ROLE_LABEL='مشرف الشركة (Company Admin)'` to override the profile badge.

`patrol_cli` still invokes `xcodebuild build-for-testing` with `-destination generic/platform=iOS Simulator` (upstream behavior). This repo pins **arm64-only** simulator builds for all `*-dev` configurations via `ios/Flutter/Dev-simulator-arch.xcconfig` and `pod install` so Runner and Pods do not link an **x86_64** slice against arm64-only Flutter simulator artifacts.

Override the sim with `PATROL_IOS_SIM_UDID` if needed (same value as `-d`).

## Smoke assertions

1. `Firebase.app().options.projectId` is **`tashil-dev`**.
2. Dummy login on the dev supervisor account (`01500000002` by default) via phone + secret fields (same as Maestro).
3. Post-login: `tashil_main_menu_button` → **الملف الشخصي** → phone visible + role badge **`مشرف الشركة (Company Admin)`** for `01500000002` (overridable).

Helpers live under `patrol_test/support/` only — no `lib/` edits.

## Frozen manifest

After a green `build-for-testing`, run `./scripts/patrol_ios_dev_freeze_manifest.sh <shortsha>` on Mac; see `patrol_test/manifest/README.md`.
