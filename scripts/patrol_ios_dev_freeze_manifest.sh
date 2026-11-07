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
  if [[ ! -e "$1" ]]; then
    echo "error: missing artifact: $1" >&2
    exit 1
  fi
  shasum -a 256 "$1" | awk '{print $1}'
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

XCTESTRUN=""
while IFS= read -r -d '' f; do
  XCTESTRUN="$f"
  break
done < <(find "$ROOT/build" -name '*.xctestrun' -print 2>/dev/null | head -n 1)

RUNNER_EXEC="$APP/Runner"
INFO_PLIST="$APP/Info.plist"
GSP="$APP/GoogleService-Info.plist"

mkdir -p "$OUT_DIR"

sha_runner="$(hash_file "$RUNNER_EXEC")"
sha_plist="$(hash_file "$INFO_PLIST")"
sha_gsp=""
if [[ -f "$GSP" ]]; then sha_gsp="$(hash_file "$GSP")"; fi
sha_xctest=""
sha_xctest_bundle=""
if [[ -n "$XCTEST" ]]; then
  sha_xctest_bundle="$(hash_file "$XCTEST")"
  XCTEST_BIN="$XCTEST/RunnerUITests"
  if [[ -f "$XCTEST_BIN" ]]; then sha_xctest="$(hash_file "$XCTEST_BIN")"; fi
fi
sha_xctestrun=""
if [[ -n "$XCTESTRUN" ]]; then sha_xctestrun="$(hash_file "$XCTESTRUN")"; fi

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
