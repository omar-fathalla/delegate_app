#!/usr/bin/env bash
# TA-49: prove android_dev_distribute.sh refuses wrong Firebase project/app targets.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

SCRIPT="$ROOT/scripts/android_dev_distribute.sh"
[[ -f "$SCRIPT" ]]

expect_fail() {
  local label="$1"
  shift
  set +e
  "$@"
  local rc=$?
  set -e
  if [[ $rc -eq 0 ]]; then
    echo "android_dev_distribute_guard: FAIL: expected refusal for $label" >&2
    exit 1
  fi
}

bash "$SCRIPT" --self-check

expect_fail "bad env project" \
  env FIREBASE_ANDROID_DEV_PROJECT=practice-firebase-72df1 bash "$SCRIPT" --dry-run

expect_fail "bad env app" \
  env FIREBASE_ANDROID_DEV_APP_ID=1:999:android:bad bash "$SCRIPT" --dry-run

expect_fail "bad cli --project" bash "$SCRIPT" --dry-run -- --project practice-firebase-72df1

expect_fail "bad cli --app" bash "$SCRIPT" --dry-run -- --app 1:0:android:evil

echo "android_dev_distribute_guard: OK"