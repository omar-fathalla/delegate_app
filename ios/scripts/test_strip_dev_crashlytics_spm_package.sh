#!/usr/bin/env bash
# Linux/CI-safe unit test for strip_dev_crashlytics_spm_package.sh (no Xcode).
set -euo pipefail

IOS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STRIP_SCRIPT="$IOS_ROOT/scripts/strip_dev_crashlytics_spm_package.sh"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

mkdir -p "$WORKDIR/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage"
MANIFEST="$WORKDIR/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift"

cat >"$MANIFEST" <<'SWIFT'
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "FlutterGeneratedPluginSwiftPackage",
  platforms: [.iOS("15.0")],
  products: [
    .library(name: "FlutterGeneratedPluginSwiftPackage", targets: ["FlutterGeneratedPluginSwiftPackage"])
  ],
  dependencies: [
    .package(name: "firebase_core", path: "../.packages/firebase_core"),
    .package(name: "firebase_crashlytics", path: "../.packages/firebase_crashlytics"),
  ],
  targets: [
    .target(
      name: "FlutterGeneratedPluginSwiftPackage",
      dependencies: [
        .product(name: "firebase-core", package: "firebase_core"),
        .product(name: "firebase-crashlytics", package: "firebase_crashlytics"),
      ]
    ),
  ]
)
SWIFT

export SRCROOT="$WORKDIR"
export CONFIGURATION=Debug-dev
/bin/sh "$STRIP_SCRIPT"

if grep -qi crashlytics "$MANIFEST"; then
  echo "test_strip_dev_crashlytics_spm_package: dev strip failed — crashlytics still in Package.swift" >&2
  exit 1
fi
if ! grep -q 'firebase_core' "$MANIFEST"; then
  echo "test_strip_dev_crashlytics_spm_package: firebase_core must remain" >&2
  exit 1
fi

cat >"$MANIFEST" <<'SWIFT'
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
export CONFIGURATION=Debug-prod
if ! SRCROOT="$WORKDIR" CONFIGURATION=Debug-prod /bin/sh "$STRIP_SCRIPT"; then
  echo "test_strip_dev_crashlytics_spm_package: prod check should pass when crashlytics present" >&2
  exit 1
fi

export CONFIGURATION=Debug-prod
cat >"$MANIFEST" <<'SWIFT'
dependencies: []
SWIFT
set +e
SRCROOT="$WORKDIR" CONFIGURATION=Debug-prod /bin/sh "$STRIP_SCRIPT" >/dev/null 2>&1
code=$?
set -e
if [ "$code" -eq 0 ]; then
  echo "test_strip_dev_crashlytics_spm_package: prod must fail closed without crashlytics" >&2
  exit 1
fi

echo "test_strip_dev_crashlytics_spm_package: OK"
