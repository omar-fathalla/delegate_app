#!/bin/sh
# Prepare the Objective-C plugin registrant used at compile time.
#
# Flutter generates `Runner/GeneratedPluginRegistrant.m` (tracked only as a template in git;
# normally gitignored). That file must never be modified in place.
#
# This script runs after Flutter's Xcode build step (`xcode_backend.sh` build). It writes a
# **derived** copy only — under **DERIVED_FILE_DIR** (per-configuration, per-target), so concurrent
# dev + prod builds do not race on one shared path under Runner/:
#   `$(DERIVED_FILE_DIR)/tashil_registrant/GeneratedPluginRegistrant.m`
#
# - Dev configurations (`Debug-dev`, `Profile-dev`, `Release-dev`): copy from the generated
#   file and strip Firebase Crashlytics registration (native plugin not registered on dev).
# - All other configurations (prod): copy verbatim so the derived file always matches Flutter's
#   generated registrant (Crashlytics remains registered). Fails the build if Crashlytics
#   registration would be missing after copy.
#
# The Xcode target compiles the derived `.m` file, not `Runner/GeneratedPluginRegistrant.m`.
# See `ios/config/README.md`.
set -eu

SOURCE="${SRCROOT:?}/Runner/GeneratedPluginRegistrant.m"
# Xcode sets DERIVED_FILE_DIR per configuration; fallback only for ad-hoc runs (e.g. tests).
DERIVED_BASE="${DERIVED_FILE_DIR:-${SRCROOT:?}/Runner/.tashil_registrant_derived}"
DERIVED_DIR="${DERIVED_BASE}/tashil_registrant"
DERIVED="${DERIVED_DIR}/GeneratedPluginRegistrant.m"

if [ ! -f "$SOURCE" ]; then
  echo "error: [Tashil derived registrant] missing generated file: $SOURCE (run Flutter build first)" >&2
  exit 1
fi

mkdir -p "$DERIVED_DIR"

case "${CONFIGURATION:-}" in
  Debug-dev|Profile-dev|Release-dev)
    exec python3 - "$SOURCE" "$DERIVED" <<'PY'
import re
import sys
from pathlib import Path

source_path = Path(sys.argv[1])
dest_path = Path(sys.argv[2])
text = source_path.read_text(encoding="utf-8")
low = text.lower()

# Dev-only strip — write only to derived path; never mutate `source_path`.
if "crashlytics" not in low:
    print("[Tashil derived registrant] OK (dev): no Crashlytics in source; writing derived copy.")
    dest_path.write_text(text, encoding="utf-8")
    sys.exit(0)

lines = text.splitlines(keepends=True)
out: list[str] = []
i = 0
crash_block = re.compile(
    r"#\s*if\b.*firebase_crashlytics",
    re.IGNORECASE,
)
reg_line = re.compile(
    r"(FLTFirebaseCrashlyticsPlugin|FirebaseCrashlyticsPlugin).*registerWithRegistrar",
)

while i < len(lines):
    line = lines[i]
    if crash_block.search(line):
        depth = 0
        while i < len(lines):
            cur = lines[i]
            st = cur.lstrip()
            if st.startswith("#if"):
                depth += 1
            elif st.startswith("#endif"):
                depth -= 1
                i += 1
                if depth == 0:
                    break
                continue
            i += 1
        continue
    if reg_line.search(line):
        i += 1
        continue
    out.append(line)
    i += 1

new_text = "".join(out)
if re.search(r"crashlytics", new_text, re.IGNORECASE):
    print("error: [Tashil derived registrant] Crashlytics references remain after strip.", file=sys.stderr)
    sys.exit(1)

dest_path.write_text(new_text, encoding="utf-8")
print("[Tashil derived registrant] OK (dev): wrote stripped derived GeneratedPluginRegistrant.m.")
PY
    ;;
  *)
    cp -f "$SOURCE" "$DERIVED"
    if ! grep -q 'FLTFirebaseCrashlyticsPlugin registerWithRegistrar' "$DERIVED" \
      && ! grep -q 'FirebaseCrashlyticsPlugin registerWithRegistrar' "$DERIVED"
    then
      echo "error: [Tashil derived registrant] prod/non-dev build requires Crashlytics plugin registration in derived registrant (see $DERIVED)." >&2
      exit 1
    fi
    echo "[Tashil derived registrant] OK (${CONFIGURATION:-unknown}): copied generated registrant to derived path (Crashlytics present)."
    ;;
esac
