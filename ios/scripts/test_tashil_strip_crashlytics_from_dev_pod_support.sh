#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STRIP="${SCRIPT_DIR}/tashil_strip_crashlytics_from_dev_pod_support.sh"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

mkdir -p "$WORKDIR/Pods/Target Support Files/Pods-Runner"
cat >"$WORKDIR/Pods/Target Support Files/Pods-Runner/Pods-Runner.debug-dev.xcconfig" <<'EOF'
OTHER_LDFLAGS = $(inherited) -framework FirebaseCrashlytics -framework FirebaseCore
FRAMEWORK_SEARCH_PATHS = $(inherited) "${PODS_ROOT}/FirebaseCrashlytics"
EOF
printf '%s\n' '${BUILT_PRODUCTS_DIR}/FirebaseCrashlytics/FirebaseCrashlytics.framework' \
  >"$WORKDIR/Pods/Target Support Files/Pods-Runner/Pods-Runner-frameworks-debug-dev-output-files.xcfilelist"

/bin/sh "$STRIP" "$WORKDIR"

if grep -qi crashlytics "$WORKDIR/Pods/Target Support Files/Pods-Runner/Pods-Runner.debug-dev.xcconfig"; then
  echo "test: debug-dev xcconfig still mentions Crashlytics" >&2
  exit 1
fi
if grep -qi crashlytics "$WORKDIR/Pods/Target Support Files/Pods-Runner/Pods-Runner-frameworks-debug-dev-output-files.xcfilelist"; then
  echo "test: output xcfilelist still mentions Crashlytics" >&2
  exit 1
fi
if ! grep -q FirebaseCore "$WORKDIR/Pods/Target Support Files/Pods-Runner/Pods-Runner.debug-dev.xcconfig"; then
  echo "test: xcconfig should keep non-Crashlytics Firebase" >&2
  exit 1
fi

echo "test_tashil_strip_crashlytics_from_dev_pod_support: OK"
