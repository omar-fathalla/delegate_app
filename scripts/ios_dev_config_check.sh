#!/usr/bin/env bash
# Static iOS dev/prod Firebase wiring checks (runs on Linux CI).
#
# Also supports optional post-build inspection (fixture .app tree or a real
# build path from macOS):
#   bash scripts/ios_dev_config_check.sh --app-path /path/to/Runner.app
# Rules for --app-path: no practice-firebase-72df1 in plists under the .app;
# for dev, Info.plist must have Crashlytics/data-collection flags off (same
# keys as ios/scripts/firebase_config.sh install / tashil_plist_tools patch-info).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_PATH=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-path)
      shift
      [[ -n "${1:-}" ]] || { echo "ios-dev-config-check: ERROR: --app-path needs a value" >&2; exit 1; }
      APP_PATH="$1"
      shift
      ;;
    *)
      echo "ios-dev-config-check: ERROR: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

fail() {
  echo "ios-dev-config-check: ERROR: $*" >&2
  exit 1
}

echo "== Repo root: $ROOT"

assert_no_crashlytics_upload_in_pbxproj() {
  if grep -E 'upload-symbols|FirebaseCrashlytics/run' ios/Runner.xcodeproj/project.pbxproj >/dev/null 2>&1; then
    fail "upload-symbols or FirebaseCrashlytics run script found in pbxproj"
  fi
  if ! grep -q 'strip_dev_crashlytics_plugin_registration' ios/Runner.xcodeproj/project.pbxproj; then
    fail "project.pbxproj missing derived registrant Run Script (strip_dev_crashlytics_plugin_registration.sh)"
  fi
  if ! grep -q '\[Tashil\] Derived plugin registrant' ios/Runner.xcodeproj/project.pbxproj; then
    fail "project.pbxproj missing [Tashil] Derived plugin registrant build phase"
  fi
  if ! grep -q 'DERIVED_FILE_DIR' ios/Runner.xcodeproj/project.pbxproj; then
    fail "project.pbxproj missing DERIVED_FILE_DIR for derived registrant"
  fi
  if ! grep -q 'tashil_registrant/GeneratedPluginRegistrant.m' ios/Runner.xcodeproj/project.pbxproj; then
    fail "project.pbxproj missing derived registrant path (tashil_registrant under DERIVED_FILE_DIR)"
  fi
  if ! grep -q 'tashil_after_flutter_xcode_backend.sh' ios/Runner.xcodeproj/project.pbxproj; then
    fail "project.pbxproj must chain tashil_after_flutter_xcode_backend.sh after xcode_backend build"
  fi
  if grep -q 'Strip dev Crashlytics SPM' ios/Runner.xcodeproj/project.pbxproj; then
    fail "standalone [Tashil] Strip dev Crashlytics SPM phase must not exist (use in-phase strip)"
  fi
  if ! grep -q 'tashil_dev_build_context.sh' ios/scripts/strip_dev_crashlytics_plugin_registration.sh; then
    fail "derived registrant script must invoke dev SPM strip before compile"
  fi
}

check_built_app() {
  local app="$1"
  local env_label="$2"
  [[ -d "$app" ]] || fail "--app-path not a directory: $app"

  echo "== Post-build inspection: $app ($env_label)"

  if grep -rl --include='*.plist' 'practice-firebase-72df1' "$app" >/dev/null 2>&1; then
    fail "built app contains practice-firebase-72df1 in a plist"
  fi

  local info
  info="$app/Info.plist"
  [[ -f "$info" ]] || fail "missing Info.plist at $info"

  local env
  env="$(python3 ios/scripts/tashil_plist_tools.py get "$info" TashilEnv 2>/dev/null | tr -d '\r\n' || true)"
  if [[ "$env_label" == dev ]]; then
    [[ "$env" == "dev" ]] || fail "expected TashilEnv=dev in built Info.plist, got '$env'"
    local gs
    gs="$app/GoogleService-Info.plist"
    [[ -f "$gs" ]] || fail "dev .app missing $gs"
    local pid
    pid="$(python3 ios/scripts/tashil_plist_tools.py get "$gs" PROJECT_ID 2>/dev/null | tr -d '\r\n' || true)"
    [[ "$pid" == "tashil-dev" ]] || fail "dev built app: GoogleService-Info PROJECT_ID must be tashil-dev (got '$pid')"
    for key in FirebaseCrashlyticsCollectionEnabled FirebaseAutomaticDataCollectionEnabled; do
      local v
      v="$(python3 ios/scripts/tashil_plist_tools.py get "$info" "$key" 2>/dev/null | tr -d '\r\n' || true)"
      [[ "$v" == "false" ]] || fail "dev Info.plist: expected $key false, got '$v'"
    done
  fi
}

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

assert_no_crashlytics_upload_in_pbxproj

grep -q 'keychain-access-groups' ios/Runner/Runner-dev.entitlements \
  || fail "Runner-dev.entitlements must declare keychain-access-groups for Firebase Auth"
grep -q 'tashil_dev_build_context.sh' ios/scripts/tashil_after_flutter_xcode_backend.sh \
  || fail "tashil_after_flutter_xcode_backend.sh must source tashil_dev_build_context"

echo "== strip_dev_crashlytics_spm_package unit test"
bash ios/scripts/test_strip_dev_crashlytics_spm_package.sh

# CI uses committed fixture as the dev GoogleService-Info (no secrets).
FIXTURE_DEV="ios/config/test/GoogleService-Info-tashil-dev.fixture.plist"
[[ -f "$FIXTURE_DEV" ]] || fail "missing fixture $FIXTURE_DEV"

restore_dev_plist() {
  if [[ -n "${DEV_PLIST_SAVED:-}" ]]; then
    mv "$DEV_PLIST_SAVED" ios/config/dev/GoogleService-Info.plist
    DEV_PLIST_SAVED=""
  elif [[ -f ios/config/dev/GoogleService-Info.plist ]]; then
    rm -f ios/config/dev/GoogleService-Info.plist
  fi
}

echo "== Positive: firebase_config check with dev fixture plist"
export APP_ENV=dev
export CONFIGURATION=Debug-dev
export PRODUCT_BUNDLE_IDENTIFIER=com.tashil.delegate.dev
export SRCROOT="$ROOT/ios"
export DART_DEFINES="$(printf 'ENV=dev' | base64 | tr -d '\n')"
DEV_PLIST_SAVED=""
if [[ -f ios/config/dev/GoogleService-Info.plist ]]; then
  DEV_PLIST_SAVED="$(mktemp)"
  cp ios/config/dev/GoogleService-Info.plist "$DEV_PLIST_SAVED"
  rm -f ios/config/dev/GoogleService-Info.plist
fi
trap 'restore_dev_plist' RETURN
cp "$FIXTURE_DEV" ios/config/dev/GoogleService-Info.plist
bash ios/scripts/firebase_config.sh check || fail "firebase_config check failed for dev with fixture plist"
restore_dev_plist
trap - RETURN

echo "== Positive: firebase_config install (fixture) + dev Crashlytics plist flags"
WORKDIR="$(mktemp -d)"
mkdir -p "$WORKDIR/TashilDev.app"
cp "$FIXTURE_DEV" "$WORKDIR/TashilDev.app/GoogleService-Info.plist"
python3 - <<'PY' "$WORKDIR/TashilDev.app/Info.plist"
import plistlib
import sys
from pathlib import Path
p = Path(sys.argv[1])
d = {"CFBundleIdentifier": "com.tashil.delegate.dev", "CFBundleShortVersionString": "1.0", "CFBundleVersion": "1"}
p.write_bytes(plistlib.dumps(d, fmt=plistlib.FMT_XML))
PY
export APP_ENV=dev
export CONFIGURATION=Debug-dev
export PRODUCT_BUNDLE_IDENTIFIER=com.tashil.delegate.dev
export SRCROOT="$ROOT/ios"
export DART_DEFINES="$(printf 'ENV=dev' | base64 | tr -d '\n')"
export TARGET_BUILD_DIR="$WORKDIR"
export UNLOCALIZED_RESOURCES_FOLDER_PATH="TashilDev.app"
export INFOPLIST_PATH="TashilDev.app/Info.plist"
DEV_PLIST_SAVED=""
if [[ -f ios/config/dev/GoogleService-Info.plist ]]; then
  DEV_PLIST_SAVED="$(mktemp)"
  cp ios/config/dev/GoogleService-Info.plist "$DEV_PLIST_SAVED"
  rm -f ios/config/dev/GoogleService-Info.plist
fi
trap 'restore_dev_plist; rm -rf "$WORKDIR"' RETURN
cp "$FIXTURE_DEV" ios/config/dev/GoogleService-Info.plist
bash ios/scripts/firebase_config.sh install || fail "firebase_config install failed (dev fixture)"
restore_dev_plist

info="$WORKDIR/TashilDev.app/Info.plist"
[[ -f "$info" ]] || fail "install did not produce Info.plist at $info"
te="$(python3 ios/scripts/tashil_plist_tools.py get "$info" TashilEnv | tr -d '\r\n' || true)"
[[ "$te" == "dev" ]] || fail "after install, TashilEnv expected dev, got '$te'"
for key in FirebaseCrashlyticsCollectionEnabled FirebaseAutomaticDataCollectionEnabled; do
  v="$(python3 ios/scripts/tashil_plist_tools.py get "$info" "$key" | tr -d '\r\n' || true)"
  [[ "$v" == "false" ]] || fail "after install, $key expected false, got '$v'"
done
rm -rf "$WORKDIR"
trap - RETURN

echo "== Negative: dev with wrong PROJECT_ID in plist must fail"
WRONG_PID_DIR="$(mktemp -d)"
trap 'rm -rf "$WRONG_PID_DIR"' EXIT
mkdir -p "$WRONG_PID_DIR/config/dev"
cp "$FIXTURE_DEV" "$WRONG_PID_DIR/config/dev/GoogleService-Info.plist"
python3 - <<PY
import plistlib
from pathlib import Path
p = Path("$WRONG_PID_DIR/config/dev/GoogleService-Info.plist")
d = plistlib.loads(p.read_bytes())
d["PROJECT_ID"] = "wrong-project-not-tashil"
p.write_bytes(plistlib.dumps(d, fmt=plistlib.FMT_XML))
PY
export APP_ENV=dev
export CONFIGURATION=Debug-dev
export PRODUCT_BUNDLE_IDENTIFIER=com.tashil.delegate.dev
export SRCROOT="$WRONG_PID_DIR"
export DART_DEFINES="$(printf 'ENV=dev' | base64 | tr -d '\n')"
set +e
out="$(bash ios/scripts/firebase_config.sh check 2>&1)"
code=$?
set -e
rm -rf "$WRONG_PID_DIR"
trap - EXIT
[[ "$code" -ne 0 ]] || fail "expected failure when dev plist has wrong PROJECT_ID"
echo "$out" | grep -qi "PROJECT_ID" || fail "wrong PROJECT_ID: expected PROJECT_ID in error message"

echo "== Negative: dev configuration must not use prod Firebase plist"
PROD_IN_DEV="$(mktemp -d)"
trap 'rm -rf "$PROD_IN_DEV"' EXIT
mkdir -p "$PROD_IN_DEV/config/dev"
cp ios/config/prod/GoogleService-Info.plist "$PROD_IN_DEV/config/dev/GoogleService-Info.plist"
export APP_ENV=dev
export CONFIGURATION=Debug-dev
export PRODUCT_BUNDLE_IDENTIFIER=com.tashil.delegate.dev
export SRCROOT="$PROD_IN_DEV"
export DART_DEFINES="$(printf 'ENV=dev' | base64 | tr -d '\n')"
set +e
out="$(bash ios/scripts/firebase_config.sh check 2>&1)"
code=$?
set -e
rm -rf "$PROD_IN_DEV"
trap - EXIT
[[ "$code" -ne 0 ]] || fail "expected failure when dev uses prod GoogleService-Info.plist"
echo "$out" | grep -qiE "PROJECT_ID|practice-firebase|BUNDLE_ID" || fail "prod-in-dev error message unclear"

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

# Prod with ENV=dev must fail
export APP_ENV=prod
export CONFIGURATION=Debug-prod
export PRODUCT_BUNDLE_IDENTIFIER=com.tashil.delegate
export SRCROOT="$ROOT/ios"
export DART_DEFINES="$(printf 'ENV=dev' | base64 | tr -d '\n')"
set +e
out="$(bash ios/scripts/firebase_config.sh check 2>&1)"
code=$?
set -e
[[ "$code" -ne 0 ]] || fail "expected failure when APP_ENV=prod and ENV=dev"
echo "$out" | grep -qi "prod" || fail "prod+ENV=dev error message missing"

if [[ -n "$APP_PATH" ]]; then
  env_guess="unknown"
  if python3 ios/scripts/tashil_plist_tools.py get "$APP_PATH/Info.plist" TashilEnv 2>/dev/null | grep -qx dev; then
    env_guess=dev
  elif python3 ios/scripts/tashil_plist_tools.py get "$APP_PATH/Info.plist" TashilEnv 2>/dev/null | grep -qx prod; then
    env_guess=prod
  fi
  if [[ "$env_guess" == dev ]]; then
    check_built_app "$APP_PATH" dev
  else
    check_built_app "$APP_PATH" prod
    echo "== (prod .app) skipped dev-only Crashlytics flag checks"
  fi
else
  echo "== Post-build .app simulation (fixture tree, dev rules)"
  SIM="$(mktemp -d)"
  trap 'rm -rf "$SIM"' EXIT
  mkdir -p "$SIM/Fake.app"
  cp "$FIXTURE_DEV" "$SIM/Fake.app/GoogleService-Info.plist"
  python3 - <<'PY' "$SIM/Fake.app/Info.plist"
import plistlib
import sys
from pathlib import Path
p = Path(sys.argv[1])
d = {"CFBundleIdentifier": "com.tashil.delegate.dev", "CFBundleShortVersionString": "1.0", "CFBundleVersion": "1"}
p.write_bytes(plistlib.dumps(d, fmt=plistlib.FMT_XML))
PY
  python3 ios/scripts/tashil_plist_tools.py patch-info "$SIM/Fake.app/Info.plist" dev
  # patch-info overwrites file; ensure CFBundleIdentifier exists for realism
  python3 - <<PY
import plistlib
from pathlib import Path
p = Path("$SIM/Fake.app/Info.plist")
d = plistlib.loads(p.read_bytes())
d["CFBundleIdentifier"] = "com.tashil.delegate.dev"
p.write_bytes(plistlib.dumps(d, fmt=plistlib.FMT_XML))
PY
  check_built_app "$SIM/Fake.app" dev
  rm -rf "$SIM"
  trap - EXIT
fi

echo "== Negative: dev --app-path with TashilEnv=dev but wrong PROJECT_ID in bundled plist"
BAD_SIM="$(mktemp -d)"
trap 'rm -rf "$BAD_SIM"' EXIT
mkdir -p "$BAD_SIM/Bad.app"
cp "$FIXTURE_DEV" "$BAD_SIM/Bad.app/GoogleService-Info.plist"
BAD_GS="$BAD_SIM/Bad.app/GoogleService-Info.plist"
python3 - "$BAD_GS" <<'PY'
import plistlib
import sys
from pathlib import Path
p = Path(sys.argv[1])
d = plistlib.loads(p.read_bytes())
d["PROJECT_ID"] = "not-tashil-dev"
p.write_bytes(plistlib.dumps(d, fmt=plistlib.FMT_XML))
PY
python3 - <<'PY' "$BAD_SIM/Bad.app/Info.plist"
import plistlib
import sys
from pathlib import Path
p = Path(sys.argv[1])
d = {"CFBundleIdentifier": "com.tashil.delegate.dev", "CFBundleShortVersionString": "1.0", "CFBundleVersion": "1"}
p.write_bytes(plistlib.dumps(d, fmt=plistlib.FMT_XML))
PY
python3 ios/scripts/tashil_plist_tools.py patch-info "$BAD_SIM/Bad.app/Info.plist" dev
outf="$(mktemp)"
set +e
( check_built_app "$BAD_SIM/Bad.app" dev ) >"$outf" 2>&1
code=$?
set -e
rm -rf "$BAD_SIM"
trap - EXIT
[[ "$code" -ne 0 ]] || fail "expected check_built_app failure for dev with wrong PROJECT_ID"
grep -q "PROJECT_ID" "$outf" || fail "wrong PROJECT_ID: expected PROJECT_ID in error message"
rm -f "$outf"

echo "ios-dev-config-check: OK"
