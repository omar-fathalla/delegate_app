#!/usr/bin/env bash
# Static: Info.plist BGTaskSchedulerPermittedIdentifiers must include offlineSyncTask,
# and AppDelegate must cold-register the same id before every return in didFinishLaunching.
set -euo pipefail

IOS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
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

validate_appdelegate_file() {
  local swift_file=$1
  python3 - "$swift_file" "$TASK_ID" <<'PY'
import re
import sys
from pathlib import Path


def strip_swift_comments(source: str) -> str:
    out: list[str] = []
    i = 0
    n = len(source)
    while i < n:
        ch = source[i]
        if ch == '"':
            out.append(ch)
            i += 1
            while i < n:
                c = source[i]
                if c == "\\" and i + 1 < n:
                    out.append(c)
                    out.append(source[i + 1])
                    i += 2
                    continue
                out.append(c)
                i += 1
                if c == '"':
                    break
            continue
        if source.startswith("/*", i):
            i += 2
            while i < n and not source.startswith("*/", i):
                i += 1
            i += 2 if i < n else 0
            out.append(" ")
            continue
        if source.startswith("//", i):
            while i < n and source[i] != "\n":
                i += 1
            out.append("\n")
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def extract_did_finish_launching_body(source: str) -> str:
    m = re.search(
        r"func application\(\s*_ application: UIApplication,\s*"
        r"didFinishLaunchingWithOptions[^)]*\)\s*-> Bool\s*\{",
        source,
        re.S,
    )
    if not m:
        raise SystemExit("didFinishLaunchingWithOptions not found")

    body_start = m.end()
    depth = 1
    i = body_start
    while i < len(source) and depth > 0:
        c = source[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
        i += 1
    return source[body_start : i - 1]


def find_offline_sync_registration(body: str, task_id: str) -> int | None:
    pattern = re.compile(
        r"WorkmanagerPlugin\.registerPeriodicTask\s*\(\s*"
        r"[\s\S]*?"
        rf'withIdentifier:\s*"{re.escape(task_id)}"'
        r"[\s\S]*?"
        r"earliestBeginInSeconds:\s*120",
        re.S,
    )
    m = pattern.search(body)
    return m.start() if m else None


def return_statement_positions(body: str) -> list[int]:
    return [m.start() for m in re.finditer(r"\breturn\b", body)]


def validate_swift(path: Path, task_id: str) -> None:
    raw = path.read_text(encoding="utf-8")
    body_raw = extract_did_finish_launching_body(raw)
    body = strip_swift_comments(body_raw)

    reg_pos = find_offline_sync_registration(body, task_id)
    if reg_pos is None:
        raise SystemExit(
            f'no live WorkmanagerPlugin.registerPeriodicTask(withIdentifier: "{task_id}", '
            "earliestBeginInSeconds: 120) in didFinishLaunching (comments ignored)"
        )

    returns = return_statement_positions(body)
    if not returns:
        raise SystemExit("didFinishLaunching has no return statements (unexpected)")

    for pos in returns:
        if reg_pos > pos:
            raise SystemExit(
                "registerPeriodicTask must precede every return "
                f"(registration at {reg_pos}, return at {pos})"
            )

    launch_pos = body.find("registerLaunchHandlers()")
    if launch_pos < 0:
        raise SystemExit("registerLaunchHandlers() missing in didFinishLaunching")
    if launch_pos > reg_pos:
        raise SystemExit("registerLaunchHandlers() must precede registerPeriodicTask")


path = Path(sys.argv[1])
task_id = sys.argv[2]
validate_swift(path, task_id)
PY
}

run_self_tests() {
  local workdir
  workdir="$(mktemp -d)"

  cat >"$workdir/pass.swift" <<'SWIFT'
class AppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    WorkmanagerPlugin.registerLaunchHandlers()
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "offlineSyncTask",
      earliestBeginInSeconds: 120
    )
    if bad { return false }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
SWIFT

  cat >"$workdir/fail_comments_no_live_call.swift" <<'SWIFT'
class AppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // WorkmanagerPlugin.registerPeriodicTask(withIdentifier: "offlineSyncTask", earliestBeginInSeconds: 120)
    return true
  }
}
SWIFT

  cat >"$workdir/fail_after_early_return.swift" <<'SWIFT'
class AppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    WorkmanagerPlugin.registerLaunchHandlers()
    if bad { return false }
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "offlineSyncTask",
      earliestBeginInSeconds: 120
    )
    return true
  }
}
SWIFT

  validate_appdelegate_file "$workdir/pass.swift" || fail "self-test: expected pass fixture to pass"

  set +e
  validate_appdelegate_file "$workdir/fail_comments_no_live_call.swift" >/dev/null 2>&1
  local c1=$?
  validate_appdelegate_file "$workdir/fail_after_early_return.swift" >/dev/null 2>&1
  local c2=$?
  set -e
  [[ "$c1" -ne 0 ]] || fail "self-test: comments-only fixture must fail"
  [[ "$c2" -ne 0 ]] || fail "self-test: registration-after-early-return fixture must fail"

  rm -rf "$workdir"
  ok "self-test negative fixtures reject false positives"
}

main() {
  if [[ "${1:-}" == "--self-test" ]]; then
    run_self_tests
    return 0
  fi

  run_self_tests

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

  validate_appdelegate_file "$DELEGATE"
  ok "AppDelegate live-registers $TASK_ID before every return in didFinishLaunching"
}

main "$@"
