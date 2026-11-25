#!/usr/bin/env bash
# Mac six-tool preflight (fathalla-mac / coordinator gate).
# Boots the pinned sim when needed, verifies Tashil Dev is installed, captures login-roles screenshot.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ "$(uname -s)" != Darwin ]]; then
  echo "mac-gate-preflight: SKIP (not macOS — run on fathalla-mac self-hosted worker)" >&2
  exit 0
fi

GIT_SHA="$(git rev-parse --short HEAD)"
SIM_UDID="${TASHIL_SIM_UDID:-8CD21E86-592A-4ED5-9F41-BF90CB9796C6}"
DEV_BUNDLE="com.tashil.delegate.dev"
PROJECT_STORE="${TASHIL_PROJECT_STORE:-/cursor/stores/bc-10199080-bfc7-439b-bdd9-fe57400f78e2}"
MEDIA_DIR="${TASHIL_PROJECT_STORE_MEDIA:-$PROJECT_STORE/media}"
SHOT_NAME="dev-login-roles-${GIT_SHA}.png"
SHOT_PATH="$MEDIA_DIR/$SHOT_NAME"
KEEP_BOOT="${TASHIL_PREFLIGHT_KEEP_BOOT:-0}"

fail() {
  echo "mac-gate-preflight: ERROR: $*" >&2
  exit 1
}

info() {
  echo "mac-gate-preflight: $*"
}

cleanup() {
  if [[ "$KEEP_BOOT" != 1 ]]; then
    info "shutting down simulator $SIM_UDID (set TASHIL_PREFLIGHT_KEEP_BOOT=1 to keep booted)"
    xcrun simctl shutdown "$SIM_UDID" >/dev/null 2>&1 || true
  else
    info "keeping simulator booted (TASHIL_PREFLIGHT_KEEP_BOOT=1)"
  fi
}
trap cleanup EXIT

info "worker hints: use self-hosted label fathalla-mac; Flutter 3.50.1; Patrol 4.9.0; Maestro 2.12.x"
info "project store: $PROJECT_STORE (screenshots → $MEDIA_DIR)"
info "sim UDID: $SIM_UDID · bundle: $DEV_BUNDLE · git: $GIT_SHA"

if ! xcrun simctl list devices | grep -q "$SIM_UDID"; then
  fail "simulator $SIM_UDID not found — register iPhone 17 sim on this Mac"
fi

state="$(xcrun simctl list devices booted | grep -c "$SIM_UDID" || true)"
if [[ "$state" -eq 0 ]]; then
  info "booting simulator"
  xcrun simctl boot "$SIM_UDID" || fail "simctl boot failed"
fi

if ! xcrun simctl get_app_container "$SIM_UDID" "$DEV_BUNDLE" data >/dev/null 2>&1; then
  fail "Tashil Dev ($DEV_BUNDLE) not installed on $SIM_UDID — build/install dev flavor first"
fi

export TASHIL_SIM_UDID="$SIM_UDID"
export TASHIL_PROJECT_STORE="$PROJECT_STORE"
export TASHIL_PROJECT_STORE_MEDIA="$MEDIA_DIR"
bash "$ROOT/scripts/capture-dev-login-roles-screenshot.sh" || fail "login-roles capture failed"
SHOT_PATH="$MEDIA_DIR/dev-login-roles-${GIT_SHA}.png"

# Best-effort: ensure our bundle is the foreground app (not Home/SpringBoard).
front="$(xcrun simctl spawn "$SIM_UDID" launchctl print system 2>/dev/null | grep -i "$DEV_BUNDLE" | head -1 || true)"
if [[ -z "$front" ]]; then
  info "warning: could not confirm foreground bundle via launchctl; verify screenshot shows login (مندوب / موظف إداري), not Home"
else
  info "foreground hint: $front"
fi

info "login-roles screenshot: $SHOT_PATH"
info "next: run Maestro journeys + Patrol integration via docs/testing/tool-roles.md"

echo "mac-gate-preflight: OK"
