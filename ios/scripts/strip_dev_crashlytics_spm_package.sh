#!/bin/sh
# Remove firebase_crashlytics from FlutterGeneratedPluginSwiftPackage on dev builds so the
# FirebaseCrashlytics native module is not linked and cannot log/init at startup.
#
# Runs after Flutter's Xcode "Run Script" (`xcode_backend.sh build`), which (re)generates:
#   ${SRCROOT}/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift
#
# - Dev (`Debug-dev`, `Profile-dev`, `Release-dev`): strip firebase_crashlytics package + product deps.
# - Prod / other: fail closed if firebase_crashlytics is missing from the generated manifest.
#
# When the project uses CocoaPods-only Firebase (no SPM Package.swift), this script no-ops.
set -eu

MANIFEST="${SRCROOT:?}/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift"

if [ ! -f "$MANIFEST" ]; then
  echo "[Tashil SPM] OK: no FlutterGeneratedPluginSwiftPackage/Package.swift (SPM plugins not used); skip."
  exit 0
fi

case "${CONFIGURATION:-}" in
  Debug-dev|Profile-dev|Release-dev)
    exec python3 - "$MANIFEST" <<'PY'
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
if re.search(r"firebase_crashlytics|firebase-crashlytics", new_text, re.IGNORECASE):
    print("error: [Tashil SPM] firebase_crashlytics references remain after strip.", file=sys.stderr)
    sys.exit(1)

path.write_text(new_text, encoding="utf-8")
print("[Tashil SPM] OK (dev): removed firebase_crashlytics from FlutterGeneratedPluginSwiftPackage.")
PY
    ;;
  *)
    if ! grep -qi 'firebase_crashlytics' "$MANIFEST"; then
      echo "error: [Tashil SPM] prod build requires firebase_crashlytics in FlutterGeneratedPluginSwiftPackage." >&2
      exit 1
    fi
    echo "[Tashil SPM] OK (${CONFIGURATION:-unknown}): firebase_crashlytics present in Package.swift."
    ;;
esac
