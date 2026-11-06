#!/usr/bin/env bash
# Regression test: derived plugin registrant stays correct when switching dev ↔ prod builds.
#
# Runs on macOS with Xcode only (requires xcodebuild). From repo root:
#   bash ios/scripts/test_derived_registrant_switching.sh
# Or from ios/:
#   bash scripts/test_derived_registrant_switching.sh
#
# Flow: Debug-dev build → verify shared GeneratedPluginRegistrant.m unchanged vs baseline;
# then Debug-prod → shared file still has Crashlytics; derived prod copy has Crashlytics;
# then Debug-dev again → derived dev file has no Crashlytics registration line.
#
# Parallel xcodebuild (two DERIVED_DATA dirs) is skipped here: a single workspace cannot
# safely run concurrent Flutter codegen (`xcode_backend.sh`) against the same Runner tree
# without races; use CI matrix / separate worktrees for true parallelism.
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "test_derived_registrant_switching: SKIP (requires macOS + Xcode)" >&2
  exit 0
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "test_derived_registrant_switching: SKIP (xcodebuild not found)" >&2
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$IOS_ROOT/.." && pwd)"
cd "$REPO_ROOT"

SRC_GENERATED="$IOS_ROOT/Runner/GeneratedPluginRegistrant.m"
DERIVED="$IOS_ROOT/Runner/.tashil_registrant_derived/GeneratedPluginRegistrant.m"

[[ -f "$SRC_GENERATED" ]] || {
  echo "test_derived_registrant_switching: missing $SRC_GENERATED — run flutter pub get / ios build first" >&2
  exit 1
}

baseline_copy="$(mktemp)"
cp "$SRC_GENERATED" "$baseline_copy"
trap 'rm -f "$baseline_copy"' EXIT

sha_file() {
  shasum -a 256 "$1" | awk '{print $1}'
}

build() {
  local config="$1"
  # CODE_SIGNING_ALLOWED=NO keeps CI/local from needing provisioning profiles for this check.
  xcodebuild -workspace "$IOS_ROOT/Runner.xcworkspace" \
    -scheme Runner \
    -configuration "$config" \
    -destination 'generic/platform=iOS Simulator' \
    CODE_SIGNING_ALLOWED=NO \
    build
}

check_shared_unchanged() {
  local current
  current="$(sha_file "$SRC_GENERATED")"
  local base
  base="$(sha_file "$baseline_copy")"
  [[ "$current" == "$base" ]] || {
    echo "test_derived_registrant_switching: shared GeneratedPluginRegistrant.m was modified (must stay read-only for strip script)" >&2
    exit 1
  }
}

has_crashlytics_registration() {
  grep -q 'FLTFirebaseCrashlyticsPlugin registerWithRegistrar' "$1" \
    || grep -q 'FirebaseCrashlyticsPlugin registerWithRegistrar' "$1"
}

echo "== 1/3 xcodebuild Debug-dev"
build "Debug-dev"
check_shared_unchanged
[[ -f "$DERIVED" ]] || { echo "test_derived_registrant_switching: missing derived file after dev build" >&2; exit 1; }
if has_crashlytics_registration "$DERIVED"; then
  echo "test_derived_registrant_switching: dev derived file must NOT register Crashlytics" >&2
  exit 1
fi

echo "== 2/3 xcodebuild Debug-prod"
build "Debug-prod"
check_shared_unchanged
[[ -f "$DERIVED" ]] || { echo "test_derived_registrant_switching: missing derived file after prod build" >&2; exit 1; }
if ! has_crashlytics_registration "$DERIVED"; then
  echo "test_derived_registrant_switching: prod derived file must include Crashlytics registration" >&2
  exit 1
fi

echo "== 3/3 xcodebuild Debug-dev (again)"
build "Debug-dev"
check_shared_unchanged
if has_crashlytics_registration "$DERIVED"; then
  echo "test_derived_registrant_switching: dev derived file must NOT register Crashlytics after prod→dev" >&2
  exit 1
fi

echo "test_derived_registrant_switching: OK"
