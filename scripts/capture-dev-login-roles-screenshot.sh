#!/usr/bin/env bash
# Capture media/dev-login-roles-<git-short>.png for six-tool gate (Maestro preferred; simctl fallback).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

GIT_SHA="$(git rev-parse --short HEAD)"
SIM_UDID="${TASHIL_SIM_UDID:-8CD21E86-592A-4ED5-9F41-BF90CB9796C6}"
DEV_BUNDLE="com.tashil.delegate.dev"
PROJECT_STORE="${TASHIL_PROJECT_STORE:-/cursor/stores/bc-10199080-bfc7-439b-bdd9-fe57400f78e2}"
MEDIA_DIR="${TASHIL_PROJECT_STORE_MEDIA:-$PROJECT_STORE/media}"
OUT="$MEDIA_DIR/dev-login-roles-${GIT_SHA}.png"

fail() {
  echo "capture-dev-login-roles: ERROR: $*" >&2
  exit 1
}

info() {
  echo "capture-dev-login-roles: $*"
}

mkdir -p "$MEDIA_DIR"

capture_via_maestro() {
  command -v maestro >/dev/null 2>&1 || return 1
  local args=()
  if [[ -n "${MAESTRO_DEVICE_ID:-}" ]]; then
    args+=(--device "$MAESTRO_DEVICE_ID")
  fi
  local log="${TASHIL_MAESTRO_LOG:-$ROOT/maestro/logs/dev-login-roles-${GIT_SHA}.log}"
  mkdir -p "$(dirname "$log")"
  maestro test "${args[@]}" maestro/flows/dev-login-roles-screenshot.yaml 2>&1 | tee "$log" || return 1
  local shot
  shot="$(find "$HOME/.maestro/tests" -type f -name '*dev-login-roles*.png' 2>/dev/null | sort -r | head -1)"
  [[ -n "$shot" && -f "$shot" ]] || fail "Maestro takeScreenshot artifact not found under ~/.maestro/tests"
  cp "$shot" "$OUT"
}

capture_via_simctl() {
  [[ "$(uname -s)" == Darwin ]] || fail "simctl capture requires macOS"
  xcrun simctl list devices | grep -q "$SIM_UDID" || fail "simulator $SIM_UDID not found"
  if ! xcrun simctl list devices booted | grep -q "$SIM_UDID"; then
    info "booting simulator $SIM_UDID"
    xcrun simctl boot "$SIM_UDID"
  fi
  xcrun simctl get_app_container "$SIM_UDID" "$DEV_BUNDLE" data >/dev/null 2>&1 \
    || fail "Tashil Dev not installed on $SIM_UDID"
  xcrun simctl terminate "$SIM_UDID" "$DEV_BUNDLE" >/dev/null 2>&1 || true
  xcrun simctl launch "$SIM_UDID" "$DEV_BUNDLE" >/dev/null
  sleep 8
  xcrun simctl io "$SIM_UDID" screenshot "$OUT"
}

if capture_via_maestro; then
  info "Maestro capture OK"
elif capture_via_simctl 2>/dev/null; then
  info "simctl capture OK (Maestro unavailable or flow failed)"
else
  fail "could not capture login-roles screenshot (need Maestro on Mac or booted sim)"
fi

[[ -s "$OUT" ]] || fail "output missing: $OUT"
info "wrote $OUT"
echo "capture-dev-login-roles: OK"
