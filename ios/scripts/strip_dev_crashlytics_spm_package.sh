#!/bin/sh
# Remove firebase_crashlytics from FlutterGeneratedPluginSwiftPackage on dev builds so the
# FirebaseCrashlytics native module is not linked and cannot log/init at startup.
#
# Invoked from: Podfile pre_install, tashil_before_flutter_xcode_backend.sh,
# xcode_backend post-hook, derived registrant prep, and Podfile post_install
# (see ios/scripts/tashil_dev_build_context.sh).
#
# - Dev (`Debug-dev`, `Profile-dev`, `Release-dev` or APP_ENV=dev): strip manifest + plugin symlink.
# - Prod / other: fail closed if firebase_crashlytics is missing from the generated manifest.
#
# When the project uses CocoaPods-only Firebase (no SPM Package.swift), this script no-ops.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
# shellcheck source=tashil_dev_build_context.sh
. "${SCRIPT_DIR}/tashil_dev_build_context.sh"

MANIFEST="${SRCROOT:?}/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift"
CRASHLYTICS_LINK="${SRCROOT:?}/Flutter/ephemeral/Packages/.packages/firebase_crashlytics"

remove_dev_swiftpm_resolved_caches() {
  for resolved in \
    "${SRCROOT}/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved" \
    "${SRCROOT}/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
  do
    if [ ! -f "$resolved" ]; then
      continue
    fi
    if grep -qi 'crashlytics' "$resolved"; then
      rm -f "$resolved"
      echo "[Tashil SPM] OK (dev): removed SwiftPM Package.resolved (Crashlytics pins)."
    fi
  done
}

remove_crashlytics_symlink() {
  if [ -L "$CRASHLYTICS_LINK" ] || [ -d "$CRASHLYTICS_LINK" ]; then
    rm -rf "$CRASHLYTICS_LINK"
    echo "[Tashil SPM] OK (dev): removed firebase_crashlytics SPM symlink."
  fi
}

if tashil_is_dev_build; then
  remove_crashlytics_symlink
  remove_dev_swiftpm_resolved_caches
  if [ ! -f "$MANIFEST" ]; then
    echo "[Tashil SPM] OK (dev): no FlutterGeneratedPluginSwiftPackage/Package.swift; skip manifest strip."
    exit 0
  fi
  python3 - "$MANIFEST" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
low = text.lower()

if "firebase_crashlytics" not in low and "firebase-crashlytics" not in low:
    print("[Tashil SPM] OK (dev): Package.swift has no firebase_crashlytics; unchanged.")
    sys.exit(0)

lines = text.splitlines(keepends=True)
out: list[str] = []
pkg_line = re.compile(
    r'\.package\s*\(\s*name:\s*"firebase_crashlytics"',
    re.IGNORECASE,
)
prod_line = re.compile(
    r'\.product\s*\(\s*name:\s*"firebase-crashlytics"\s*,\s*package:\s*"firebase_crashlytics"',
    re.IGNORECASE,
)

for line in lines:
    if pkg_line.search(line) or prod_line.search(line):
        continue
    out.append(line)

new_text = "".join(out)
new_text = re.sub(r",\s*\]", "]", new_text)
new_text = re.sub(r"\[\s*,", "[", new_text)
new_text = re.sub(r",\s*,", ",", new_text)
if re.search(r"firebase_crashlytics|firebase-crashlytics", new_text, re.IGNORECASE):
    print("error: [Tashil SPM] firebase_crashlytics references remain after strip.", file=sys.stderr)
    sys.exit(1)

path.write_text(new_text, encoding="utf-8")
print("[Tashil SPM] OK (dev): removed firebase_crashlytics from FlutterGeneratedPluginSwiftPackage.")
PY
  remove_dev_swiftpm_resolved_caches
else
  if [ ! -f "$MANIFEST" ]; then
    echo "[Tashil SPM] OK: no FlutterGeneratedPluginSwiftPackage/Package.swift (SPM plugins not used); skip."
    exit 0
  fi
  if ! grep -qi 'firebase_crashlytics' "$MANIFEST"; then
    echo "error: [Tashil SPM] prod build requires firebase_crashlytics in FlutterGeneratedPluginSwiftPackage." >&2
    exit 1
  fi
  echo "[Tashil SPM] OK (${CONFIGURATION:-unknown}): firebase_crashlytics present in Package.swift."
fi
