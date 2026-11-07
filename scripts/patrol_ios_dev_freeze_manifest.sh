#!/usr/bin/env bash
# Freeze SHA-256 manifest for PR #218 Patrol iOS dev sim User Test.
# Run on Mac from a clean worktree at the target commit (see patrol_test/manifest/README.md).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SHORT_SHA="${1:-$(git rev-parse --short=7 HEAD)}"
FULL_SHA="$(git rev-parse HEAD)"
OUT_DIR="$ROOT/patrol_test/manifest"
RESOLVER="$OUT_DIR/xctestrun_resolve.py"
YAML="$OUT_DIR/frozen-${SHORT_SHA}.yaml"
JSON="$OUT_DIR/frozen-${SHORT_SHA}.json"
IOS_INTEG="$ROOT/build/ios_integ"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "error: worktree is not clean; commit or stash before freezing manifest" >&2
  exit 1
fi

if [[ "$(git rev-parse --short=7 HEAD)" != "$SHORT_SHA" ]]; then
  echo "error: HEAD short SHA does not match requested $SHORT_SHA" >&2
  exit 1
fi

hash_file() {
  if [[ ! -f "$1" ]]; then
    echo "error: missing artifact: $1" >&2
    exit 1
  fi
  shasum -a 256 "$1" | awk '{print $1}'
}

# Deterministic directory fingerprint: sorted relative paths + per-file sha256 manifest.
hash_directory() {
  local dir="$1"
  if [[ ! -d "$dir" ]]; then
    echo "error: missing directory: $dir" >&2
    exit 1
  fi
  local manifest
  manifest="$(mktemp)"
  while IFS= read -r -d '' f; do
    local rel="${f#"$dir"/}"
    local h
    h="$(shasum -a 256 "$f" | awk '{print $1}')"
    printf '%s\t%s\n' "$rel" "$h"
  done < <(find "$dir" -type f -print0 | LC_ALL=C sort -z) >"$manifest"
  shasum -a 256 "$manifest" | awk '{print $1}'
  rm -f "$manifest"
}

file_mtime() {
  local f="$1"
  if stat -f %m "$f" >/dev/null 2>&1; then
    stat -f %m "$f"
  else
    stat -c %Y "$f"
  fi
}

find_latest_xctestrun() {
  local dir="$1"
  if [[ ! -d "$dir" ]]; then
    return 1
  fi
  local best_mtime=0
  local best_path=""
  while IFS= read -r -d '' f; do
    local mt
    mt="$(file_mtime "$f")"
    if [[ "$mt" -ge "$best_mtime" ]]; then
      best_mtime="$mt"
      best_path="$f"
    fi
  done < <(find "$dir" -name '*.xctestrun' -type f -print0 2>/dev/null)
  if [[ -n "$best_path" ]]; then
    printf '%s' "$best_path"
    return 0
  fi
  return 1
}

XCTESTRUN=""
if XCTESTRUN="$(find_latest_xctestrun "$IOS_INTEG")"; then
  :
else
  echo "error: no .xctestrun under build/ios_integ; run patrol build-for-testing first" >&2
  exit 1
fi

if [[ ! -f "$RESOLVER" ]]; then
  echo "error: missing resolver: $RESOLVER" >&2
  exit 1
fi

# shellcheck disable=SC1090
while IFS='=' read -r key value; do
  [[ -z "$key" ]] && continue
  case "$key" in
    blueprint_name) BLUEPRINT_NAME="$value" ;;
    ui_target_app) APP="$value" ;;
    test_runner_app) TEST_RUNNER="$value" ;;
    test_bundle) XCTEST="$value" ;;
    raw_test_host_path) RAW_TEST_HOST="$value" ;;
    raw_test_bundle_path) RAW_TEST_BUNDLE="$value" ;;
    raw_ui_target_app_path) RAW_UI_TARGET="$value" ;;
    xctestrun_format_version) XCTESTRUN_FORMAT="$value" ;;
  esac
done < <(python3 "$RESOLVER" "$XCTESTRUN")

: "${APP:?resolver did not set ui_target_app}"
: "${TEST_RUNNER:?resolver did not set test_runner_app}"
: "${XCTEST:?resolver did not set test_bundle}"
: "${BLUEPRINT_NAME:=RunnerUITests}"

for required_dir in "$APP" "$TEST_RUNNER" "$XCTEST"; do
  if [[ ! -d "$required_dir" ]]; then
    echo "error: xctestrun references missing path: $required_dir" >&2
    exit 1
  fi
done

mkdir -p "$OUT_DIR"

RUNNER_EXEC="$APP/Runner"
INFO_PLIST="$APP/Info.plist"
GSP="$APP/GoogleService-Info.plist"

sha_runner="$(hash_file "$RUNNER_EXEC")"
sha_plist="$(hash_file "$INFO_PLIST")"
sha_gsp=""
if [[ -f "$GSP" ]]; then sha_gsp="$(hash_file "$GSP")"; fi
sha_app_tree="$(hash_directory "$APP")"
sha_test_runner_tree="$(hash_directory "$TEST_RUNNER")"
sha_xctest_bundle="$(hash_directory "$XCTEST")"

XCTEST_BIN=""
for candidate in "$XCTEST/RunnerUITests" "$XCTEST/$(basename "$XCTEST" .xctest)"; do
  if [[ -f "$candidate" ]]; then
    XCTEST_BIN="$candidate"
    break
  fi
done
sha_xctest=""
if [[ -n "$XCTEST_BIN" ]]; then
  sha_xctest="$(hash_file "$XCTEST_BIN")"
fi

sha_xctestrun="$(hash_file "$XCTESTRUN")"
CAPTURED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

cat >"$YAML" <<EOF
# Frozen Patrol iOS dev sim artifacts @ $FULL_SHA
git_commit: $FULL_SHA
git_short: $SHORT_SHA
bundle_id: com.tashil.delegate.dev
firebase_project_id: tashil-dev
captured_at: "$CAPTURED_AT"
xctestrun:
  path: $XCTESTRUN
  format_version: ${XCTESTRUN_FORMAT:-1}
  blueprint_name: $BLUEPRINT_NAME
  keys:
    UITargetAppPath: "$RAW_UI_TARGET"
    TestHostPath: "$RAW_TEST_HOST"
    TestBundlePath: "$RAW_TEST_BUNDLE"
  sha256: $sha_xctestrun
artifacts:
  runner_app:
    source: xctestrun UITargetAppPath
    path: $APP
    sha256:
      tree: $sha_app_tree
      Runner: $sha_runner
      Info.plist: $sha_plist
      GoogleService-Info.plist: ${sha_gsp:-null}
  test_runner:
    source: xctestrun TestHostPath
    path: $TEST_RUNNER
    sha256:
      tree: $sha_test_runner_tree
  runner_ui_tests:
    source: xctestrun TestBundlePath
    path: $XCTEST
    sha256:
      bundle: $sha_xctest_bundle
      RunnerUITests: ${sha_xctest:-null}
EOF

# JSON via python for correct escaping of paths
export FULL_SHA SHORT_SHA CAPTURED_AT XCTESTRUN XCTESTRUN_FORMAT BLUEPRINT_NAME
export RAW_UI_TARGET RAW_TEST_HOST RAW_TEST_BUNDLE sha_xctestrun
export APP TEST_RUNNER XCTEST
export sha_app_tree sha_runner sha_plist sha_gsp sha_test_runner_tree
export sha_xctest_bundle sha_xctest

python3 - <<'PY' >"$JSON"
import json, os

def v(name, default=None):
    return os.environ.get(name, default)

payload = {
    "git_commit": v("FULL_SHA"),
    "git_short": v("SHORT_SHA"),
    "bundle_id": "com.tashil.delegate.dev",
    "firebase_project_id": "tashil-dev",
    "captured_at": v("CAPTURED_AT"),
    "xctestrun": {
        "path": v("XCTESTRUN"),
        "format_version": int(v("XCTESTRUN_FORMAT", "1")),
        "blueprint_name": v("BLUEPRINT_NAME"),
        "keys": {
            "UITargetAppPath": v("RAW_UI_TARGET"),
            "TestHostPath": v("RAW_TEST_HOST"),
            "TestBundlePath": v("RAW_TEST_BUNDLE"),
        },
        "sha256": v("sha_xctestrun"),
    },
    "artifacts": {
        "runner_app": {
            "source": "xctestrun UITargetAppPath",
            "path": v("APP"),
            "sha256": {
                "tree": v("sha_app_tree"),
                "Runner": v("sha_runner"),
                "Info.plist": v("sha_plist"),
                "GoogleService-Info.plist": v("sha_gsp") or None,
            },
        },
        "test_runner": {
            "source": "xctestrun TestHostPath",
            "path": v("TEST_RUNNER"),
            "sha256": {"tree": v("sha_test_runner_tree")},
        },
        "runner_ui_tests": {
            "source": "xctestrun TestBundlePath",
            "path": v("XCTEST"),
            "sha256": {
                "bundle": v("sha_xctest_bundle"),
                "RunnerUITests": v("sha_xctest") or None,
            },
        },
    },
}
print(json.dumps(payload, indent=2))
PY

echo "Wrote $YAML"
echo "Wrote $JSON"
