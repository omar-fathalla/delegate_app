#!/usr/bin/env bash
# Run PR #215 supervisor Maestro flow (secrets via env only — never commit).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FLOW_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="$FLOW_DIR/logs"
LOG="${TASHIL_MAESTRO_LOG:-$LOG_DIR/supervisor-identity-persist.log}"

: "${TASHIL_MAESTRO_DEV_SECRET:?Export TASHIL_MAESTRO_DEV_SECRET from coordinator internal/tashil-dev-test-accounts.txt (never commit).}"

export TASHIL_MAESTRO_DEV_PHONE="${TASHIL_MAESTRO_DEV_PHONE:-01500000002}"
export TASHIL_MAESTRO_DEV_SECRET

mkdir -p "$LOG_DIR"

ARGS=()
if [[ -n "${MAESTRO_DEVICE_ID:-}" ]]; then
  ARGS+=(--device "$MAESTRO_DEVICE_ID")
fi

cd "$FLOW_DIR"
# shellcheck disable=SC2068
maestro test "${ARGS[@]}" "flows/pr215-supervisor-identity-persist.yaml" 2>&1 | tee "$LOG"
