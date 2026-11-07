#!/usr/bin/env bash
# Quick check: derived registrant output is isolated per CONFIGURATION/DERIVED_FILE_DIR
# (no shared path under Runner/ when two builds use different derived dirs).
#
# macOS only. From repo root:
#   bash ios/scripts/test_derived_registrant_path_isolation.sh
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "test_derived_registrant_path_isolation: SKIP (requires macOS)" >&2
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STRIP_SCRIPT="$IOS_ROOT/scripts/strip_dev_crashlytics_plugin_registration.sh"

TMP_BASE="$(mktemp -d)"
trap 'rm -rf "$TMP_BASE"' EXIT

# Minimal fake `ios/` tree — never touches the repo’s Runner/ (Flutter may have generated .m).
FAKE_IOS="$TMP_BASE/fake_ios"
mkdir -p "$FAKE_IOS/Runner"
cat >"$FAKE_IOS/Runner/GeneratedPluginRegistrant.m" <<'OBJC'
// Fixture for path isolation test (not full Flutter output).
#import "GeneratedPluginRegistrant.h"

@implementation GeneratedPluginRegistrant

+ (void)registerWithRegistry:(id)registry {
#if canImport(firebase_crashlytics)
  [FLTFirebaseCrashlyticsPlugin registerWithRegistrar:[registry registrarForPlugin:@"FLTFirebaseCrashlyticsPlugin"]];
#endif
}

@end
OBJC

run_strip() {
  local cfg="$1"
  local ddir="$2"
  mkdir -p "$ddir"
  SRCROOT="$FAKE_IOS" DERIVED_FILE_DIR="$ddir" CONFIGURATION="$cfg" /bin/sh "$STRIP_SCRIPT"
}

DD_DEV="$TMP_BASE/dev_dfd"
DD_PROD="$TMP_BASE/prod_dfd"

run_strip "Debug-dev" "$DD_DEV"
run_strip "Debug-prod" "$DD_PROD"

DEV_DERIVED="$DD_DEV/tashil_registrant/GeneratedPluginRegistrant.m"
PROD_DERIVED="$DD_PROD/tashil_registrant/GeneratedPluginRegistrant.m"

[[ -f "$DEV_DERIVED" ]] || {
  echo "test_derived_registrant_path_isolation: missing $DEV_DERIVED" >&2
  exit 1
}
[[ -f "$PROD_DERIVED" ]] || {
  echo "test_derived_registrant_path_isolation: missing $PROD_DERIVED" >&2
  exit 1
}
[[ "$DEV_DERIVED" != "$PROD_DERIVED" ]] || {
  echo "test_derived_registrant_path_isolation: dev and prod paths must differ" >&2
  exit 1
}

if grep -q 'FLTFirebaseCrashlyticsPlugin registerWithRegistrar' "$DEV_DERIVED" \
  || grep -q 'FirebaseCrashlyticsPlugin registerWithRegistrar' "$DEV_DERIVED"
then
  echo "test_derived_registrant_path_isolation: dev derived must not register Crashlytics" >&2
  exit 1
fi

if ! grep -q 'FLTFirebaseCrashlyticsPlugin registerWithRegistrar' "$PROD_DERIVED"; then
  echo "test_derived_registrant_path_isolation: prod derived must include Crashlytics registration" >&2
  exit 1
fi

echo "test_derived_registrant_path_isolation: OK"
