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

# TAS-394: every target needs its own -t. With one -t followed by bare paths,
# patrol_cli keeps only the first path (the rest go to argResults.rest, which
# `patrol test` ignores), so from #228 (8 Nov) until this fix only the first
# file ever ran.
args=()
for t in "${targets[@]}"; do
  args+=(-t "$t")
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
args+=(${extra[@]+"${extra[@]}"})  # bash 3.2 + set -u: empty array

if [[ "${PATROL_RUN_DRY:-0}" == "1" ]]; then
  # Prints the command (secrets masked) for the -t regression test.
  printf '%s\n' "patrol test ${args[*]}" | sed -E 's/(SECRET=)[^ ]*/\1***/g'
  exit 0
fi

# TAS-394 guard: patrol prints one result line per test ending in
# "(/<file>.dart)". A target with no such line never ran, which must fail the
# gate even when everything that did run passed.
log="$(mktemp -t patrol-run.XXXXXX)"
set +e
patrol test "${args[@]}" 2>&1 | tee "$log"
status=${PIPESTATUS[0]}
set -e
bash "$ROOT/scripts/patrol_check_ran_targets.sh" "$log" "${targets[@]}" || status=1
rm -f "$log"
exit "$status"
