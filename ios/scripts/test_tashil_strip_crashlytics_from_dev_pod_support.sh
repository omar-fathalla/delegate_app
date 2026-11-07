#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STRIP="${SCRIPT_DIR}/tashil_strip_crashlytics_from_dev_pod_support.sh"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

mkdir -p "$WORKDIR/Pods/Target Support Files/Pods-Runner"

# Mac @ 5d1e196 orphan -framework pattern (regression).
cat >"$WORKDIR/Pods/Target Support Files/Pods-Runner/Pods-Runner.debug-dev.xcconfig" <<'EOF'
OTHER_LDFLAGS = $(inherited) -framework "firebase_core" -framework "FirebaseCrashlytics" -framework "firebase_messaging"
FRAMEWORK_SEARCH_PATHS = $(inherited) "${PODS_ROOT}/GoogleMaps/Base" "${PODS_ROOT}/FirebaseCrashlytics"
EOF

printf '%s\n' \
  '${BUILT_PRODUCTS_DIR}/FirebaseCrashlytics/FirebaseCrashlytics.framework' \
  '${BUILT_PRODUCTS_DIR}/firebase_messaging.framework' \
  >"$WORKDIR/Pods/Target Support Files/Pods-Runner/Pods-Runner-frameworks-debug-dev-output-files.xcfilelist"

/bin/sh "$STRIP" "$WORKDIR"

XC="$WORKDIR/Pods/Target Support Files/Pods-Runner/Pods-Runner.debug-dev.xcconfig"
grep -qi crashlytics "$XC" && { echo "test: xcconfig still mentions Crashlytics" >&2; exit 1; }
grep -qF -- '-framework -framework' "$XC" && { echo "test: orphan -framework pair remains" >&2; exit 1; }
grep -q 'firebase_core' "$XC" || { echo "test: firebase_core missing" >&2; exit 1; }
grep -q 'firebase_messaging' "$XC" || { echo "test: firebase_messaging missing" >&2; exit 1; }
grep -q 'GoogleMaps' "$XC" || { echo "test: GoogleMaps search path missing" >&2; exit 1; }

LIST="$WORKDIR/Pods/Target Support Files/Pods-Runner/Pods-Runner-frameworks-debug-dev-output-files.xcfilelist"
grep -qi crashlytics "$LIST" && { echo "test: output xcfilelist still has Crashlytics" >&2; exit 1; }
grep -q firebase_messaging "$LIST" || { echo "test: messaging framework should remain in embed list" >&2; exit 1; }

# Simulated post-strip Mac breakage.
echo 'OTHER_LDFLAGS = $(inherited) -framework "firebase_core" -framework -framework "firebase_messaging"' >"$XC"
/bin/sh "$STRIP" "$WORKDIR"
grep -qF -- '-framework -framework' "$XC" && { echo "test: failed to collapse orphan -framework" >&2; exit 1; }

echo "test_tashil_strip_crashlytics_from_dev_pod_support: OK"
