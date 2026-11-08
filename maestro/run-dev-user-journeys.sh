#!/usr/bin/env bash
# Black-box Maestro user journeys (tashil-dev). No secrets in repo — pass via -e / env.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

: "${TASHIL_MAESTRO_DEV_SECRET:?Set TASHIL_MAESTRO_DEV_SECRET from Project store only}"

PHONE="${TASHIL_MAESTRO_DEV_PHONE:-01500000002}"
DELEGATE_PHONE="${TASHIL_MAESTRO_DEV_DELEGATE_PHONE:-01500000003}"
DELEGATE_NID="${TASHIL_MAESTRO_DEV_DELEGATE_NATIONAL_ID:-29901015740919}"

MAESTRO_ARGS=(
  -e "TASHIL_MAESTRO_DEV_PHONE=${PHONE}"
  -e "TASHIL_MAESTRO_DEV_SECRET=${TASHIL_MAESTRO_DEV_SECRET}"
  -e "TASHIL_MAESTRO_DEV_DELEGATE_PHONE=${DELEGATE_PHONE}"
  -e "TASHIL_MAESTRO_DEV_DELEGATE_NATIONAL_ID=${DELEGATE_NID}"
)

if [[ -n "${MAESTRO_DEVICE_ID:-}" ]]; then
  maestro test --device "$MAESTRO_DEVICE_ID" "${MAESTRO_ARGS[@]}" \
    maestro/flows/dev-staff-navigation-logout.yaml
  maestro test --device "$MAESTRO_DEVICE_ID" "${MAESTRO_ARGS[@]}" \
    maestro/flows/dev-delegate-navigation-logout.yaml
else
  maestro test "${MAESTRO_ARGS[@]}" maestro/flows/dev-staff-navigation-logout.yaml
  maestro test "${MAESTRO_ARGS[@]}" maestro/flows/dev-delegate-navigation-logout.yaml
fi
