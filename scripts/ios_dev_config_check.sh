#!/usr/bin/env bash
# Static iOS dev/prod Firebase wiring checks (runs on Linux CI).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() {
  echo "ios-dev-config-check: ERROR: $*" >&2
  exit 1
}

echo "== Repo root: $ROOT"

# 1) Dev plist path is gitignored and documented; prod plist must exist and be prod project.
[[ -f ios/config/prod/GoogleService-Info.plist ]] || fail "missing ios/config/prod/GoogleService-Info.plist"
grep -q 'practice-firebase-72df1' ios/config/prod/GoogleService-Info.plist \
  || fail "prod plist missing practice-firebase-72df1"
python3 ios/scripts/tashil_plist_tools.py get ios/config/prod/GoogleService-Info.plist PROJECT_ID \
  | grep -qx 'practice-firebase-72df1' || fail "prod plist PROJECT_ID parse mismatch"

if [[ -f ios/config/dev/GoogleService-Info.plist ]]; then
  echo "== Optional dev plist present: validating content"
  pid="$(python3 ios/scripts/tashil_plist_tools.py get ios/config/dev/GoogleService-Info.plist PROJECT_ID || true)"
  [[ "$pid" == "tashil-dev" ]] || fail "dev GoogleService-Info.plist PROJECT_ID must be tashil-dev (got $pid)"
  bid="$(python3 ios/scripts/tashil_plist_tools.py get ios/config/dev/GoogleService-Info.plist BUNDLE_ID || true)"
  [[ "$bid" == "com.tashil.delegate.dev" ]] || fail "dev BUNDLE_ID must be com.tashil.delegate.dev (got $bid)"
  if grep -q 'practice-firebase-72df1' ios/config/dev/GoogleService-Info.plist; then
    fail "dev plist must not mention practice-firebase-72df1"
  fi
else
  echo "== No ios/config/dev/GoogleService-Info.plist (OK for CI; required locally for dev builds)"
fi

grep -q 'ios/config/dev/GoogleService-Info.plist' .gitignore || fail ".gitignore must ignore dev plist"

grep -q 'FirebaseApp.configure' ios/Runner/AppDelegate.swift || fail "AppDelegate missing Firebase call"
# Strip // comments so docstrings mentioning configure() do not false-positive.
if sed 's|//.*||' ios/Runner/AppDelegate.swift | awk '/case "dev":/,/^    default:/{print}' | grep -q 'FirebaseApp\.configure'; then
  fail "FirebaseApp.configure must not appear in dev branch"
fi

if grep -E 'upload-symbols|FirebaseCrashlytics/run' ios/Runner.xcodeproj/project.pbxproj >/dev/null 2>&1; then
  fail "upload-symbols or FirebaseCrashlytics run script found in pbxproj"
fi

# ENV vs APP_ENV: simulate prod Debug-prod (no dart define => prod)
export APP_ENV=prod
export CONFIGURATION=Debug-prod
export PRODUCT_BUNDLE_IDENTIFIER=com.tashil.delegate
export SRCROOT="$ROOT/ios"
unset DART_DEFINES
bash ios/scripts/firebase_config.sh check || fail "firebase_config check failed for prod"

# Dev without ENV=dev must fail
export APP_ENV=dev
export CONFIGURATION=Debug-dev
export PRODUCT_BUNDLE_IDENTIFIER=com.tashil.delegate.dev
unset DART_DEFINES
set +e
out="$(bash ios/scripts/firebase_config.sh check 2>&1)"
code=$?
set -e
[[ "$code" -ne 0 ]] || fail "expected failure when APP_ENV=dev and ENV unset"
echo "$out" | grep -q "ENV=" || fail "dev mismatch error message missing"

# Dev with wrong ENV must fail
export DART_DEFINES="$(printf 'ENV=prod' | base64 | tr -d '\n')"
set +e
out="$(bash ios/scripts/firebase_config.sh check 2>&1)"
code=$?
set -e
[[ "$code" -ne 0 ]] || fail "expected failure when APP_ENV=dev and ENV=prod"
echo "$out" | grep -q "flavor dev" || fail "wrong ENV error message missing"

# Dev with ENV=dev must pass only when dev plist exists
export DART_DEFINES="$(printf 'ENV=dev' | base64 | tr -d '\n')"
if [[ -f ios/config/dev/GoogleService-Info.plist ]]; then
  bash ios/scripts/firebase_config.sh check || fail "firebase_config check failed for dev with plist"
else
  set +e
  out="$(bash ios/scripts/firebase_config.sh check 2>&1)"
  code=$?
  set -e
  [[ "$code" -ne 0 ]] || fail "expected failure: dev plist missing in CI"
  echo "$out" | grep -q 'missing' || fail "expected missing dev plist error in output"
fi

echo "ios-dev-config-check: OK"
