#!/bin/sh
# Remove firebase_crashlytics from FlutterGeneratedPluginSwiftPackage on dev builds so the
# FirebaseCrashlytics native module is not linked and cannot log/init at startup.
#
# Invoked from: dev scheme pre-build, Podfile pre_install, tashil_before_flutter_xcode_backend.sh,
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

purge_dev_swiftpm_resolve_files() {
  for resolved in \
    "${SRCROOT}/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved" \
    "${SRCROOT}/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
  do
    if [ -f "$resolved" ]; then
      rm -f "$resolved"
      echo "[Tashil SPM] OK (dev): removed SwiftPM Package.resolved (force re-resolve without Crashlytics)."
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
  purge_dev_swiftpm_resolve_files
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

if not re.search(r"crashlytics|firebase-crashlytics", low):
    print("[Tashil SPM] OK (dev): Package.swift has no Crashlytics references; unchanged.")
    sys.exit(0)

lines = text.splitlines(keepends=True)
out: list[str] = []
crash_line = re.compile(r"crashlytics|firebase-crashlytics", re.IGNORECASE)

for line in lines:
    if crash_line.search(line):
        continue
    out.append(line)

new_text = "".join(out)
new_text = re.sub(r",\s*\]", "]", new_text)
new_text = re.sub(r"\[\s*,", "[", new_text)
new_text = re.sub(r",\s*,", ",", new_text)
if re.search(r"crashlytics|firebase-crashlytics", new_text, re.IGNORECASE):
    print("error: [Tashil SPM] Crashlytics references remain after strip.", file=sys.stderr)
    sys.exit(1)

path.write_text(new_text, encoding="utf-8")
print("[Tashil SPM] OK (dev): removed Crashlytics from FlutterGeneratedPluginSwiftPackage.")
PY
  purge_dev_swiftpm_resolve_files
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
