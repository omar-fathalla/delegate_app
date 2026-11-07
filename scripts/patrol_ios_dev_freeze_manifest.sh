#!/usr/bin/env bash
# Freeze SHA-256 manifest for PR #218 Patrol iOS dev sim User Test.
# Run on Mac from a clean worktree at the target commit (see patrol_test/manifest/README.md).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SHORT_SHA="${1:-$(git rev-parse --short=7 HEAD)}"
FULL_SHA="$(git rev-parse HEAD)"
OUT_DIR="$ROOT/patrol_test/manifest"
YAML="$OUT_DIR/frozen-${SHORT_SHA}.yaml"
JSON="$OUT_DIR/frozen-${SHORT_SHA}.json"

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

APP_CANDIDATES=(
  "$ROOT/build/ios/iphonesimulator/Runner.app"
  "$ROOT/build/ios_integ/Build/Products/Debug-dev-iphonesimulator/Runner.app"
)
APP=""
for c in "${APP_CANDIDATES[@]}"; do
  if [[ -d "$c" ]]; then APP="$c"; break; fi
done
if [[ -z "$APP" ]]; then
  echo "error: Runner.app not found; run patrol build-for-testing or flutter build ios first" >&2
  exit 1
fi

PRODUCTS_DIR="$(cd "$(dirname "$APP")" && pwd)"
XCTEST=""
for c in \
  "$PRODUCTS_DIR/RunnerUITests-RunnerUITests.xctest" \
  "$PRODUCTS_DIR/RunnerUITests.xctest" \
  "$ROOT/build/ios_integ/Build/Products/Debug-dev-iphonesimulator/RunnerUITests-RunnerUITests.xctest"; do
  if [[ -d "$c" ]]; then XCTEST="$c"; break; fi
done

XCTESTRUN="$(find "$ROOT/build" -name '*.xctestrun' 2>/dev/null | LC_ALL=C sort | head -n 1 || true)"

RUNNER_EXEC="$APP/Runner"
INFO_PLIST="$APP/Info.plist"
GSP="$APP/GoogleService-Info.plist"

mkdir -p "$OUT_DIR"

sha_runner="$(hash_file "$RUNNER_EXEC")"
sha_plist="$(hash_file "$INFO_PLIST")"
sha_gsp=""
if [[ -f "$GSP" ]]; then sha_gsp="$(hash_file "$GSP")"; fi
sha_app_tree="$(hash_directory "$APP")"
sha_xctest=""
sha_xctest_bundle=""
if [[ -n "$XCTEST" ]]; then
  sha_xctest_bundle="$(hash_directory "$XCTEST")"
  XCTEST_BIN="$XCTEST/RunnerUITests"
  if [[ -f "$XCTEST_BIN" ]]; then sha_xctest="$(hash_file "$XCTEST_BIN")"; fi
fi
sha_xctestrun=""
if [[ -n "$XCTESTRUN" && -f "$XCTESTRUN" ]]; then sha_xctestrun="$(hash_file "$XCTESTRUN")"; fi

CAPTURED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

cat >"$YAML" <<EOF
# Frozen Patrol iOS dev sim artifacts @ $FULL_SHA
git_commit: $FULL_SHA
git_short: $SHORT_SHA
bundle_id: com.tashil.delegate.dev
firebase_project_id: tashil-dev
captured_at: "$CAPTURED_AT"
artifacts:
  runner_app:
    path: $APP
    sha256:
      tree: $sha_app_tree
      Runner: $sha_runner
      Info.plist: $sha_plist
      GoogleService-Info.plist: ${sha_gsp:-null}
  runner_ui_tests:
    path: ${XCTEST:-null}
    sha256:
      bundle: ${sha_xctest_bundle:-null}
      RunnerUITests: ${sha_xctest:-null}
  xctestrun:
    path: ${XCTESTRUN:-null}
    sha256: ${sha_xctestrun:-null}
EOF

cat >"$JSON" <<EOF
{
  "git_commit": "$FULL_SHA",
  "git_short": "$SHORT_SHA",
  "bundle_id": "com.tashil.delegate.dev",
  "firebase_project_id": "tashil-dev",
  "captured_at": "$CAPTURED_AT",
  "artifacts": {
    "runner_app": {
      "path": "$APP",
      "sha256": {
        "tree": "$sha_app_tree",
        "Runner": "$sha_runner",
        "Info.plist": "$sha_plist",
        "GoogleService-Info.plist": "${sha_gsp:-null}"
      }
    },
    "runner_ui_tests": {
      "path": "${XCTEST:-null}",
      "sha256": {
        "bundle": "${sha_xctest_bundle:-null}",
        "RunnerUITests": "${sha_xctest:-null}"
      }
    },
    "xctestrun": {
      "path": "${XCTESTRUN:-null}",
      "sha256": "${sha_xctestrun:-null}"
    }
  }
}
EOF

echo "Wrote $YAML"
echo "Wrote $JSON"
