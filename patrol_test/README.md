# Patrol iOS dev smoke (PR #218)

## Command (Mac)

Use a **concrete simulator UDID** so the run phase targets the right device (Mohamed default: iPhone 17 `8CD21E86-592A-4ED5-9F41-BF90CB9796C6`):

```bash
patrol test \
  -t patrol_test/smoke_dev_login_test.dart \
  --flavor dev \
  --dart-define=ENV=dev \
  -d 8CD21E86-592A-4ED5-9F41-BF90CB9796C6
```

`patrol_cli` still invokes `xcodebuild build-for-testing` with `-destination generic/platform=iOS Simulator` (upstream behavior). This repo pins **arm64-only** simulator builds for all `*-dev` configurations via `ios/Flutter/Dev-simulator-arch.xcconfig` and `pod install` so Runner and Pods do not link an **x86_64** slice against arm64-only Flutter simulator artifacts.

Override the sim with `PATROL_IOS_SIM_UDID` if needed (same value as `-d`).

## Smoke assertions

The dev login smoke does **not** log in. It waits for splash/auto-login to settle, taps `splash_sign_in` when the stall UI appears, then asserts the delegate login screen using the ENV=dev Maestro semantics id `tashil_login_submit`, with fallback to the phone field icon (`Icons.phone_android_rounded`).
