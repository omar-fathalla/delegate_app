#!/usr/bin/env bash
# Black-box Maestro user journeys (tashil-dev). No secrets in repo — pass via -e / env.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
LOG_DIR="${TASHIL_MAESTRO_LOG_DIR:-$ROOT/maestro/logs}"
SHORT_SHA="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
LOG="${TASHIL_MAESTRO_LOG:-$LOG_DIR/maestro_dev_journeys_${SHORT_SHA}.log}"

: "${TASHIL_MAESTRO_DEV_SECRET:?Set TASHIL_MAESTRO_DEV_SECRET from Project store only}"

mkdir -p "$LOG_DIR"
if [[ "${TASHIL_CAPTURE_LOGIN_ROLES:-1}" == 1 ]]; then
  bash "$ROOT/scripts/capture-dev-login-roles-screenshot.sh" || true
fi

PHONE="${TASHIL_MAESTRO_DEV_PHONE:-01500000002}"
DELEGATE_PHONE="${TASHIL_MAESTRO_DEV_DELEGATE_PHONE:-01500000003}"
DELEGATE_NID="${TASHIL_MAESTRO_DEV_DELEGATE_NATIONAL_ID:-29901015740919}"

MAESTRO_ARGS=(
  -e "TASHIL_MAESTRO_DEV_PHONE=${PHONE}"
  -e "TASHIL_MAESTRO_DEV_SECRET=${TASHIL_MAESTRO_DEV_SECRET}"
  -e "TASHIL_MAESTRO_DEV_DELEGATE_PHONE=${DELEGATE_PHONE}"
  -e "TASHIL_MAESTRO_DEV_DELEGATE_NATIONAL_ID=${DELEGATE_NID}"
)

run_one() {
  maestro test "$@" 2>&1 | tee -a "$LOG"
}

if [[ -n "${MAESTRO_DEVICE_ID:-}" ]]; then
  run_one --device "$MAESTRO_DEVICE_ID" "${MAESTRO_ARGS[@]}" \
    maestro/flows/dev-staff-navigation-logout.yaml
  run_one --device "$MAESTRO_DEVICE_ID" "${MAESTRO_ARGS[@]}" \
    maestro/flows/dev-delegate-navigation-logout.yaml
else
  run_one "${MAESTRO_ARGS[@]}" maestro/flows/dev-staff-navigation-logout.yaml
  run_one "${MAESTRO_ARGS[@]}" maestro/flows/dev-delegate-navigation-logout.yaml
fi
