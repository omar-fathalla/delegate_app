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

MARKETING_PHONE="${TASHIL_MAESTRO_DEV_MARKETING_PHONE:-01000000007}"
MAESTRO_ARGS=(
  -e "TASHIL_MAESTRO_DEV_PHONE=${PHONE}"
  -e "TASHIL_MAESTRO_DEV_SECRET=${TASHIL_MAESTRO_DEV_SECRET}"
  -e "TASHIL_MAESTRO_DEV_DELEGATE_PHONE=${DELEGATE_PHONE}"
  -e "TASHIL_MAESTRO_DEV_DELEGATE_NATIONAL_ID=${DELEGATE_NID}"
  -e "TASHIL_MAESTRO_DEV_MARKETING_PHONE=${MARKETING_PHONE}"
  -e "TASHIL_MAESTRO_DEV_MARKETING_SECRET=${TASHIL_MAESTRO_DEV_MARKETING_SECRET:-}"
)

# TAS-393: the marketing journey needs its own fake account secret; without it
# the flow is skipped with a notice (the gate does not fail on a missing
# optional account).
run_marketing() {
  if [[ -z "${TASHIL_MAESTRO_DEV_MARKETING_SECRET:-}" ]]; then
    echo "maestro: TASHIL_MAESTRO_DEV_MARKETING_SECRET not set, skipping the dev-marketing-* journeys" | tee -a "$LOG"
    return 0
  fi
  local flow
  # Android device: push the fake evidence image so the gallery picker in
  # journey 5 picks it (newest photo), never a personal photo.
  if [[ -n "${MAESTRO_DEVICE_ID:-}" ]] && command -v adb >/dev/null 2>&1 \
      && adb -s "$MAESTRO_DEVICE_ID" get-state >/dev/null 2>&1; then
    adb -s "$MAESTRO_DEVICE_ID" push maestro/assets/tashil-fake-evidence.png \
      /sdcard/Pictures/tashil-fake-evidence-tas393.png >/dev/null
    adb -s "$MAESTRO_DEVICE_ID" shell am broadcast \
      -a android.intent.action.MEDIA_SCANNER_SCAN_FILE \
      -d file:///sdcard/Pictures/tashil-fake-evidence-tas393.png >/dev/null
  fi
  # Full marketing journey (TAS-393), one file per area so a failure names it.
  for flow in maestro/flows/dev-marketing-[1-5]-*.yaml; do
    run_one "$@" "${MAESTRO_ARGS[@]}" "$flow"
  done
}

run_one() {
  maestro test "$@" 2>&1 | tee -a "$LOG"
}

if [[ -n "${MAESTRO_DEVICE_ID:-}" ]]; then
  run_one --device "$MAESTRO_DEVICE_ID" "${MAESTRO_ARGS[@]}" \
    maestro/flows/dev-staff-navigation-logout.yaml
  run_one --device "$MAESTRO_DEVICE_ID" "${MAESTRO_ARGS[@]}" \
    maestro/flows/dev-delegate-navigation-logout.yaml
  run_marketing --device "$MAESTRO_DEVICE_ID"
else
  run_one "${MAESTRO_ARGS[@]}" maestro/flows/dev-staff-navigation-logout.yaml
  run_one "${MAESTRO_ARGS[@]}" maestro/flows/dev-delegate-navigation-logout.yaml
  run_marketing
fi
