#!/usr/bin/env bash
# Mac / coordinator wrapper: static Patrol guards, then patrol test (integration only).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DEFAULT_TARGETS=(
  patrol_test/integration_native_permissions_test.dart
  patrol_test/integration_location_checkin_test.dart
  patrol_test/integration_push_notification_test.dart
  patrol_test/integration_offline_sync_lifecycle_test.dart
  patrol_test/integration_marketing_floor_check_test.dart
  patrol_test/integration_marketing_export_and_dates_test.dart
  patrol_test/integration_marketing_contact_test.dart
)

targets=()
extra=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--target)
      shift
      [[ -n "${1:-}" ]] || { echo "patrol_run_dev_integration: missing value for $1" >&2; exit 1; }
      targets+=("$1")
      shift
      ;;
    --)
      shift
      extra+=("$@")
      break
      ;;
    *)
      extra+=("$1")
      shift
      ;;
  esac
done

if [[ "${#targets[@]}" -eq 0 ]]; then
  targets=("${DEFAULT_TARGETS[@]}")
fi

bash "$ROOT/scripts/patrol_check_integration_targets.sh" --targets "${targets[@]}"

if ! command -v patrol >/dev/null 2>&1; then
  echo "patrol_run_dev_integration: ERROR: patrol CLI not on PATH" >&2
  exit 1
fi

args=(-t)
for t in "${targets[@]}"; do
  args+=("$t")
done
args+=(--flavor dev --dart-define=ENV=dev)
if [[ -n "${PATROL_DEV_SECRET:-}" ]]; then
  args+=(--dart-define=PATROL_DEV_SECRET="$PATROL_DEV_SECRET")
fi
# Staff account override (local CI uses a seeded fake supervisor); delegate
# tests keep their own account.
if [[ -n "${PATROL_DEV_STAFF_PHONE:-}" ]]; then
  args+=(--dart-define=PATROL_DEV_STAFF_PHONE="$PATROL_DEV_STAFF_PHONE")
fi
if [[ -n "${PATROL_DEV_DELEGATE_PHONE:-}" ]]; then
  args+=(--dart-define=PATROL_DEV_DELEGATE_PHONE="$PATROL_DEV_DELEGATE_PHONE")
fi
# TAS-393: marketing account (skipped by the test when no secret is passed).
if [[ -n "${PATROL_DEV_MARKETING_PHONE:-}" ]]; then
  args+=(--dart-define=PATROL_DEV_MARKETING_PHONE="$PATROL_DEV_MARKETING_PHONE")
fi
if [[ -n "${PATROL_DEV_MARKETING_SECRET:-}" ]]; then
  args+=(--dart-define=PATROL_DEV_MARKETING_SECRET="$PATROL_DEV_MARKETING_SECRET")
fi
if [[ -n "${PATROL_DEV_NATIONAL_ID:-}" ]]; then
  args+=(--dart-define=PATROL_DEV_NATIONAL_ID="$PATROL_DEV_NATIONAL_ID")
fi
args+=("${extra[@]}")

exec patrol test "${args[@]}"
