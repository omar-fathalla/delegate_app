#!/usr/bin/env bash
# Unit tests for dev-flavor detection (DART_DEFINES base64 allow/deny).
set -euo pipefail

IOS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IS_DEV="${IOS_ROOT}/scripts/tashil_is_dev_build.sh"
STRIP="${IOS_ROOT}/scripts/strip_dev_crashlytics_spm_package.sh"
ENV_DEV_B64="$(printf 'ENV=dev' | base64 | tr -d '\n')"
ENV_PROD_B64="$(printf 'ENV=prod' | base64 | tr -d '\n')"
WRONG_TOKEN='RVOWPWRldg=='

assert_dev() {
  local label=$1
  shift
  if env "$@" "$IS_DEV"; then
    echo "test_tashil_dev_build_context: OK dev: $label"
  else
    echo "test_tashil_dev_build_context: FAIL expected dev for $label" >&2
    exit 1
  fi
}

assert_not_dev() {
  local label=$1
  shift
  if env "$@" "$IS_DEV"; then
    echo "test_tashil_dev_build_context: FAIL expected not-dev for $label" >&2
    exit 1
  else
    echo "test_tashil_dev_build_context: OK not-dev: $label"
  fi
}

export SRCROOT="$IOS_ROOT"

assert_dev "CONFIGURATION=Debug-dev" CONFIGURATION=Debug-dev
assert_dev "APP_ENV=dev" APP_ENV=dev
assert_dev "bundle id" PRODUCT_BUNDLE_IDENTIFIER=com.tashil.delegate.dev
assert_dev "DART_DEFINES ENV=dev" DART_DEFINES="$ENV_DEV_B64"
assert_not_dev "DART_DEFINES ENV=prod" DART_DEFINES="$ENV_PROD_B64"
assert_not_dev "wrong RVOWPWRldg token" DART_DEFINES="$WRONG_TOKEN"
assert_not_dev "empty env" env -u APP_ENV -u CONFIGURATION -u DART_DEFINES -u PRODUCT_BUNDLE_IDENTIFIER "$IS_DEV"

fixture_manifest() {
  local dest=$1
  mkdir -p "$(dirname "$dest")"
  cat >"$dest" <<'SWIFT'
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "FlutterGeneratedPluginSwiftPackage",
  dependencies: [
    .package(name: "firebase_crashlytics", path: "../.packages/firebase_crashlytics"),
  ],
  targets: [
    .target(
      name: "FlutterGeneratedPluginSwiftPackage",
      dependencies: [
        .product(name: "firebase-crashlytics", package: "firebase_crashlytics"),
      ]
    ),
  ]
)
SWIFT
}

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
mkdir -p "$WORKDIR/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage"
mkdir -p "$WORKDIR/Flutter/ephemeral/Packages/.packages"
MANIFEST="$WORKDIR/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift"
LINK="$WORKDIR/Flutter/ephemeral/Packages/.packages/firebase_crashlytics"

for pass in 1 2; do
  fixture_manifest "$MANIFEST"
  mkdir -p "$LINK"
  touch "$LINK/placeholder"
  SRCROOT="$WORKDIR" CONFIGURATION=Debug-dev APP_ENV=dev /bin/sh "$STRIP"
  if grep -qi crashlytics "$MANIFEST"; then
    echo "test_tashil_dev_build_context: pass $pass still has crashlytics in Package.swift" >&2
    exit 1
  fi
  if [ -e "$LINK" ]; then
    echo "test_tashil_dev_build_context: pass $pass firebase_crashlytics symlink/dir still present" >&2
    exit 1
  fi
done
echo "test_tashil_dev_build_context: OK repeated clean SPM strip"

if grep -q 'RVOWPWRldg==' "$IOS_ROOT/Podfile" 2>/dev/null; then
  echo "test_tashil_dev_build_context: FAIL Podfile still contains wrong RVOWPWRldg token" >&2
  exit 1
fi

echo "test_tashil_dev_build_context: all OK"
