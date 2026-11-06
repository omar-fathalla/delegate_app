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
#
# Raw `xcodebuild` needs the same prep Flutter applies (Pods + xcconfigs + module maps).
# This script runs `flutter build ios --config-only` per flavor and `pod install` before
# the dev→prod→dev sequence, without re-running Flutter between xcodebuild steps (User Test
# scenario: switch configuration in Xcode only).
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
GENERATED_XCCONFIG="$IOS_ROOT/Flutter/Generated.xcconfig"

resolve_flutter_bin() {
  if command -v flutter >/dev/null 2>&1; then
    command -v flutter
    return 0
  fi
  if [[ -f "$GENERATED_XCCONFIG" ]]; then
    # shellcheck disable=SC2002
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

prep_workspace() {
  local flutter_bin
  flutter_bin="$(resolve_flutter_bin)" || {
    echo "test_derived_registrant_switching: need flutter on PATH or valid Flutter/Generated.xcconfig (run flutter pub get)" >&2
    exit 1
  }

  echo "test_derived_registrant_switching: using flutter: $flutter_bin"
  (cd "$REPO_ROOT" && "$flutter_bin" pub get)

  # Per-flavor: regenerate iOS config and pod integration without a full compile.
  echo "test_derived_registrant_switching: flutter build ios --config-only (dev)"
  (cd "$REPO_ROOT" && "$flutter_bin" build ios --config-only --no-codesign --simulator \
    --flavor dev --dart-define=ENV=dev)
  echo "test_derived_registrant_switching: pod install (after dev config-only)"
  (cd "$IOS_ROOT" && pod install)

  echo "test_derived_registrant_switching: flutter build ios --config-only (prod)"
  (cd "$REPO_ROOT" && "$flutter_bin" build ios --config-only --no-codesign --simulator \
    --flavor prod --dart-define=ENV=prod)
  echo "test_derived_registrant_switching: pod install (after prod config-only)"
  (cd "$IOS_ROOT" && pod install)

  [[ -f "$SRC_GENERATED" ]] || {
    echo "test_derived_registrant_switching: missing $SRC_GENERATED after flutter config-only" >&2
    exit 1
  }
}

prep_workspace

baseline_copy="$(mktemp)"
cp "$SRC_GENERATED" "$baseline_copy"
trap 'rm -f "$baseline_copy"' EXIT

sha_file() {
  shasum -a 256 "$1" | awk '{print $1}'
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

build() {
  local config="$1"
  local defines
  defines="$(dart_defines_for_configuration "$config")"
  # CODE_SIGNING_ALLOWED=NO keeps CI/local from needing provisioning profiles for this check.
  # DART_DEFINES must match the configuration so firebase_config.sh and flutter_assemble agree
  # with what `flutter build` would pass (simulates switching scheme only in Xcode).
  # On Apple Silicon, `generic/platform=iOS Simulator` can produce a multi-arch slice where
  # Flutter's debug_unpack_ios lipo step fails (IOS_ARCHS / verify_arch). Exclude the unused
  # simulator arch for this host; Intel hosts exclude arm64.
  local -a xcode_excluded_arch=()
  case "$(uname -m)" in
  arm64)
    xcode_excluded_arch=(EXCLUDED_ARCHS=x86_64)
    ;;
  *)
    xcode_excluded_arch=(EXCLUDED_ARCHS=arm64)
    ;;
  esac
  xcodebuild -workspace "$IOS_ROOT/Runner.xcworkspace" \
    -scheme Runner \
    -configuration "$config" \
    -destination 'generic/platform=iOS Simulator' \
    DART_DEFINES="$defines" \
    CODE_SIGNING_ALLOWED=NO \
    "${xcode_excluded_arch[@]}" \
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
