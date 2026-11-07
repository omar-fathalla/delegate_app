#!/bin/sh
# Strip Crashlytics from *-dev CocoaPods embed/link metadata only (prod *-prod untouched).
set -eu

IOS_ROOT="${1:-$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)}"
SUPPORT="${IOS_ROOT}/Pods/Target Support Files/Pods-Runner"
if [ ! -d "$SUPPORT" ]; then
  echo "[Tashil Pods] OK: no Pods-Runner support dir; skip Crashlytics pod strip."
  exit 0
fi

sanitize_file() {
  python3 - "$1" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
lines = path.read_text(encoding="utf-8").splitlines()
out: list[str] = []
for line in lines:
    if not re.search(r"crashlytics", line, re.IGNORECASE):
        out.append(line)
        continue
    cleaned = re.sub(r"\s*-framework\s+[\"']?FirebaseCrashlytics[\"']?", "", line, flags=re.IGNORECASE)
    cleaned = re.sub(r"\s*\"[^\"]*Crashlytics[^\"]*\"", "", cleaned, flags=re.IGNORECASE)
    cleaned = re.sub(r"\s{2,}", " ", cleaned).strip()
    if re.search(r"crashlytics", cleaned, re.IGNORECASE):
        continue
    if cleaned:
        out.append(cleaned)
path.write_text("\n".join(out) + ("\n" if out else ""), encoding="utf-8")
PY
}

for cfg in debug-dev profile-dev release-dev; do
  xcconfig="${SUPPORT}/Pods-Runner.${cfg}.xcconfig"
  if [ -f "$xcconfig" ]; then
    sanitize_file "$xcconfig"
    echo "[Tashil Pods] OK: stripped Crashlytics from Pods-Runner.${cfg}.xcconfig"
  fi
  for kind in input-files output-files; do
    list="${SUPPORT}/Pods-Runner-frameworks-${cfg}-${kind}.xcfilelist"
    if [ -f "$list" ]; then
      grep -vi 'crashlytics' "$list" >"${list}.tmp" || true
      mv "${list}.tmp" "$list"
      echo "[Tashil Pods] OK: stripped Crashlytics from $(basename "$list")"
    fi
  done
done

frameworks_sh="${SUPPORT}/Pods-Runner-frameworks.sh"
if [ -f "$frameworks_sh" ] && grep -qi crashlytics "$frameworks_sh"; then
  grep -vi 'crashlytics' "$frameworks_sh" >"${frameworks_sh}.tmp" || true
  mv "${frameworks_sh}.tmp" "$frameworks_sh"
  echo "[Tashil Pods] OK: stripped Crashlytics lines from Pods-Runner-frameworks.sh"
fi
