#!/usr/bin/env bash
# Regression test: derived plugin registrant stays correct when switching dev ↔ prod builds.
#
# Runs on macOS with Flutter + Xcode (`xcodebuild -showBuildSettings` only). From repo root:
#   bash ios/scripts/test_derived_registrant_switching.sh
# Or from ios/:
#   bash scripts/test_derived_registrant_switching.sh
#
# Flow: baseline snapshot of Flutter-generated `Runner/GeneratedPluginRegistrant.m` (never
# edited in place); then **flutter build ios** simulator **dev → prod → dev** (each pass runs
# `config-only` + `pod install` so CocoaPods matches the flavor, then a full build so SwiftPM
# resolves, including the `Flutter` package — raw `xcodebuild build` alone fails on Flutter 3.44.5).
# After each build: shared generated file unchanged vs baseline; derived file under
# `$(DERIVED_FILE_DIR)/tashil_registrant/` has Crashlytics registration **only** for prod.
#
# The derived registrant path is per-configuration (`DERIVED_FILE_DIR`) so dev/prod do not race
# on one on-disk path when builds overlap.
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
GENERATED_XCCONFIG="$IOS_ROOT/Flutter/Generated.xcconfig"

resolve_flutter_bin() {
  if command -v flutter >/dev/null 2>&1; then
    command -v flutter
    return 0
  fi
  if [[ -f "$GENERATED_XCCONFIG" ]]; then
    local root
    root="$(grep -m1 '^FLUTTER_ROOT=' "$GENERATED_XCCONFIG" | sed 's/^FLUTTER_ROOT=//')"
    root="${root//[[:space:]]/}"
    if [[ -n "$root" && -x "$root/bin/flutter" ]]; then
      echo "$root/bin/flutter"
      return 0
    fi
  fi
  return 1
}

# Comma-separated base64 defines, matching Xcode / Flutter (DART_DEFINES).
encode_dart_defines() {
  local out="" item enc
  for item in "$@"; do
    enc="$(printf '%s' "$item" | base64 | tr -d '\n')"
    if [[ -z "$out" ]]; then
      out="$enc"
    else
      out="$out,$enc"
    fi
  done
  printf '%s' "$out"
}

xcode_configuration_for_flavor() {
  case "$1" in
    dev) printf '%s' "Debug-dev" ;;
    prod) printf '%s' "Debug-prod" ;;
    *)
      echo "test_derived_registrant_switching: unknown flavor: $1" >&2
      exit 1
      ;;
  esac
}

dart_defines_for_configuration() {
  case "$1" in
    Debug-dev | Profile-dev | Release-dev)
      encode_dart_defines "ENV=dev"
      ;;
    *)
      encode_dart_defines "ENV=prod"
      ;;
  esac
}

# Resolve DERIVED_FILE_DIR for a Runner configuration (no compile — SPM not required).
derived_registrant_path_for_configuration() {
  local config="$1"
  local defines
  defines="$(dart_defines_for_configuration "$config")"
  local -a xcode_flags=(
    -workspace "$IOS_ROOT/Runner.xcworkspace"
    -scheme Runner
    -configuration "$config"
    -destination 'generic/platform=iOS Simulator'
    "DART_DEFINES=$defines"
    CODE_SIGNING_ALLOWED=NO
  )
  case "$(uname -m)" in
    arm64) xcode_flags+=(EXCLUDED_ARCHS=x86_64) ;;
    *) xcode_flags+=(EXCLUDED_ARCHS=arm64) ;;
  esac
  local ddir
  ddir="$(xcodebuild "${xcode_flags[@]}" -showBuildSettings 2>/dev/null \
    | grep -m1 '^\s*DERIVED_FILE_DIR = ' \
    | sed 's/^[[:space:]]*DERIVED_FILE_DIR = //' \
    | sed 's/^"//;s/"$//' )"
  [[ -n "$ddir" ]] || {
    echo "test_derived_registrant_switching: could not resolve DERIVED_FILE_DIR for $config" >&2
    exit 1
  }
  printf '%s' "${ddir}/tashil_registrant/GeneratedPluginRegistrant.m"
}

# One flavor: config-only + pod install + full simulator debug build (SwiftPM + Flutter OK).
flutter_build_sim_flavor() {
  local flavor="$1"
  local env="$2"
  local flutter_bin="$3"
  local -a excl
  case "$(uname -m)" in
    arm64) excl=(-- "EXCLUDED_ARCHS=x86_64") ;;
    *) excl=(-- "EXCLUDED_ARCHS=arm64") ;;
  esac
  echo "test_derived_registrant_switching: flutter build ios --config-only ($flavor)"
  (cd "$REPO_ROOT" && "$flutter_bin" build ios --config-only --no-codesign --simulator \
    --flavor "$flavor" --dart-define="ENV=$env")
  echo "test_derived_registrant_switching: pod install (after $flavor config-only)"
  (cd "$IOS_ROOT" && pod install)
  echo "test_derived_registrant_switching: flutter build ios --debug --simulator ($flavor)"
  (cd "$REPO_ROOT" && "$flutter_bin" build ios --debug --no-codesign --simulator \
    --flavor "$flavor" --dart-define="ENV=$env" "${excl[@]}")
}

FLUTTER_BIN="$(resolve_flutter_bin)" || {
  echo "test_derived_registrant_switching: need flutter on PATH or valid Flutter/Generated.xcconfig (run flutter pub get)" >&2
  exit 1
}

echo "test_derived_registrant_switching: using flutter: $FLUTTER_BIN"
(cd "$REPO_ROOT" && "$FLUTTER_BIN" pub get)

echo "test_derived_registrant_switching: initial config-only (dev) + pod for workspace"
(cd "$REPO_ROOT" && "$FLUTTER_BIN" build ios --config-only --no-codesign --simulator \
  --flavor dev --dart-define=ENV=dev)
(cd "$IOS_ROOT" && pod install)

[[ -f "$SRC_GENERATED" ]] || {
  echo "test_derived_registrant_switching: missing $SRC_GENERATED after prep (run flutter pub get / config-only)" >&2
  exit 1
}

baseline_copy="$(mktemp)"
cp "$SRC_GENERATED" "$baseline_copy"
trap 'rm -f "$baseline_copy"' EXIT

sha_file() {
  shasum -a 256 "$1" | awk '{print $1}'
}

check_shared_unchanged() {
  local current base
  current="$(sha_file "$SRC_GENERATED")"
  base="$(sha_file "$baseline_copy")"
  [[ "$current" == "$base" ]] || {
    echo "test_derived_registrant_switching: shared GeneratedPluginRegistrant.m changed vs baseline (strip script must not edit in place)" >&2
    exit 1
  }
}

has_crashlytics_registration() {
  grep -q 'FLTFirebaseCrashlyticsPlugin registerWithRegistrar' "$1" \
    || grep -q 'FirebaseCrashlyticsPlugin registerWithRegistrar' "$1"
}

CONFIG_DEV="$(xcode_configuration_for_flavor dev)"
CONFIG_PROD="$(xcode_configuration_for_flavor prod)"

echo "== 1/3 flutter build dev (simulator)"
flutter_build_sim_flavor dev dev "$FLUTTER_BIN"
check_shared_unchanged
DERIVED="$(derived_registrant_path_for_configuration "$CONFIG_DEV")"
[[ -f "$DERIVED" ]] || { echo "test_derived_registrant_switching: missing derived file after dev build: $DERIVED" >&2; exit 1; }
if has_crashlytics_registration "$DERIVED"; then
  echo "test_derived_registrant_switching: dev derived file must NOT register Crashlytics" >&2
  exit 1
fi

echo "== 2/3 flutter build prod (simulator)"
flutter_build_sim_flavor prod prod "$FLUTTER_BIN"
check_shared_unchanged
DERIVED="$(derived_registrant_path_for_configuration "$CONFIG_PROD")"
[[ -f "$DERIVED" ]] || { echo "test_derived_registrant_switching: missing derived file after prod build: $DERIVED" >&2; exit 1; }
if ! has_crashlytics_registration "$DERIVED"; then
  echo "test_derived_registrant_switching: prod derived file must include Crashlytics registration" >&2
  exit 1
fi

echo "== 3/3 flutter build dev (simulator, again)"
flutter_build_sim_flavor dev dev "$FLUTTER_BIN"
check_shared_unchanged
DERIVED="$(derived_registrant_path_for_configuration "$CONFIG_DEV")"
if has_crashlytics_registration "$DERIVED"; then
  echo "test_derived_registrant_switching: dev derived file must NOT register Crashlytics after prod→dev" >&2
  exit 1
fi

echo "test_derived_registrant_switching: OK"
