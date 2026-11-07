#!/usr/bin/env bash
# Static: Info.plist BGTaskSchedulerPermittedIdentifiers must include offlineSyncTask,
# and AppDelegate must cold-register the same id before didFinishLaunching returns.
set -euo pipefail

IOS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(cd "$IOS_ROOT/.." && pwd)"
INFO="$IOS_ROOT/Runner/Info.plist"
DELEGATE="$IOS_ROOT/Runner/AppDelegate.swift"
TASK_ID="offlineSyncTask"

fail() {
  echo "test_offline_sync_bgtask_registration: FAIL: $*" >&2
  exit 1
}

ok() {
  echo "test_offline_sync_bgtask_registration: OK: $*"
}

[[ -f "$INFO" ]] || fail "missing $INFO"
[[ -f "$DELEGATE" ]] || fail "missing $DELEGATE"

if ! python3 - "$INFO" "$TASK_ID" <<'PY'
import plistlib
import sys
from pathlib import Path

info_path = Path(sys.argv[1])
task_id = sys.argv[2]
data = plistlib.loads(info_path.read_bytes())
permitted = data.get("BGTaskSchedulerPermittedIdentifiers") or []
if task_id not in permitted:
    raise SystemExit(f"BGTaskSchedulerPermittedIdentifiers missing {task_id!r} (have {permitted!r})")
PY
then
  fail "Info.plist permit list does not include $TASK_ID"
fi
ok "Info.plist lists $TASK_ID under BGTaskSchedulerPermittedIdentifiers"

if ! grep -q 'registerPeriodicTask' "$DELEGATE"; then
  fail "AppDelegate missing WorkmanagerPlugin.registerPeriodicTask"
fi
if ! grep -q "withIdentifier: \"$TASK_ID\"" "$DELEGATE"; then
  fail "AppDelegate registerPeriodicTask must use identifier $TASK_ID"
fi
if ! grep -q 'earliestBeginInSeconds: 120' "$DELEGATE"; then
  fail "AppDelegate must pass earliestBeginInSeconds: 120 (matches Dart initialDelay)"
fi

python3 - "$DELEGATE" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
m = re.search(
    r"func application\(\s*_ application: UIApplication,\s*"
    r"didFinishLaunchingWithOptions[^)]*\)\s*-> Bool\s*\{",
    text,
    re.S,
)
if not m:
    raise SystemExit("didFinishLaunchingWithOptions not found")

body_start = m.end()
# Match closing brace at same indentation as func (4 spaces before `}`)
depth = 1
i = body_start
while i < len(text) and depth > 0:
    c = text[i]
    if c == "{":
        depth += 1
    elif c == "}":
        depth -= 1
    i += 1
body = text[body_start : i - 1]

reg = body.find("registerPeriodicTask")
if reg < 0:
    raise SystemExit("registerPeriodicTask not inside didFinishLaunching")

# First return in body (exclude super.application return at end)
returns = [m.start() for m in re.finditer(r"\breturn\b", body)]
if not returns:
    raise SystemExit("no return in didFinishLaunching (unexpected)")

first_return = min(returns)
if reg > first_return:
    raise SystemExit(
        f"registerPeriodicTask must appear before first return "
        f"(register at {reg}, first return at {first_return})"
    )

if "registerLaunchHandlers()" not in body[:reg]:
    raise SystemExit("registerLaunchHandlers() must precede registerPeriodicTask")
PY
ok "AppDelegate cold-registers $TASK_ID before first return in didFinishLaunching"
