#!/bin/sh
# Dev-only: remove Firebase Crashlytics from GeneratedPluginRegistrant.m so the native
# Crashlytics plugin is never registered in Debug-dev / Profile-dev / Release-dev.
# Runs after Flutter's Xcode build step (which generates this file); idempotent.
# See ios/config/README.md.
set -eu

case "${CONFIGURATION:-}" in
  Debug-dev|Profile-dev|Release-dev) ;;
  *)
    exit 0
    ;;
esac

TARGET="${SRCROOT:?}/Runner/GeneratedPluginRegistrant.m"
if [ ! -f "$TARGET" ]; then
  echo "error: [Tashil strip-dev-crashlytics] missing $TARGET" >&2
  exit 1
fi

exec python3 - "$TARGET" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
low = text.lower()

# Already stripped (no crashlytics references)
if "crashlytics" not in low:
    print("[Tashil strip-dev-crashlytics] OK: no Crashlytics in GeneratedPluginRegistrant.m (already stripped).")
    sys.exit(0)

lines = text.splitlines(keepends=True)
out: list[str] = []
i = 0
# Match FlutterFire's #if wrapper for the firebase_crashlytics pod
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
    print("error: [Tashil strip-dev-crashlytics] Crashlytics references remain after strip.", file=sys.stderr)
    sys.exit(1)

path.write_text(new_text, encoding="utf-8")
print("[Tashil strip-dev-crashlytics] OK: removed Crashlytics from GeneratedPluginRegistrant.m.")
PY
