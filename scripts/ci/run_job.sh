#!/usr/bin/env bash
# Run one CI job from scripts/ci/jobs.sh in the current checkout.
#
#   bash scripts/ci/run_job.sh <job>
#   bash scripts/ci/run_job.sh --list
#
# Emulator jobs take a port slot lease (scripts/ci/lease.sh) unless the caller
# already holds one and exported CI_SLOT. Slot k uses ports base + k*10000
# (slot 1 = 18080/14400/19099/19199/15001/14500/19150), never the defaults,
# so a developer running `npm run test:rules` by hand never collides with CI.
#
# Env:
#   CI_SLOTS        number of port slots on this Mac (default 3)
#   CI_SLOT_WAIT    seconds to wait for a free slot (default 1800)
#   CI_SLOT         pre-acquired slot (set by local_ci.sh)
set -euo pipefail

CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=jobs.sh
source "$CI_DIR/jobs.sh"
# shellcheck source=lease.sh
source "$CI_DIR/lease.sh"

if [[ "${1:-}" == "--list" ]]; then
  for j in $CI_JOBS_ALL $CI_JOBS_DEVICE; do echo "$j"; done
  exit 0
fi

JOB="${1:-}"
if [[ -z "$JOB" ]] || ! ci_job_exists "$JOB"; then
  echo "usage: run_job.sh <job>   (jobs: $CI_JOBS_ALL)" >&2
  exit 2
fi
export CI_JOB="$JOB" CI_DIR

ci_slot_env() {
  local k="$1" off=$(( $1 * 10000 ))
  export CI_SLOT="$k"
  export LOCAL_CI_FIRESTORE_PORT=$((8080 + off))
  export LOCAL_CI_FIRESTORE_HUB_PORT=$((4400 + off))
  export LOCAL_CI_AUTH_PORT=$((9099 + off))
  export LOCAL_CI_STORAGE_PORT=$((9199 + off))
  export LOCAL_CI_FUNCTIONS_PORT=$((5001 + off))
  export LOCAL_CI_LOGGING_PORT=$((4500 + off))
  export LOCAL_CI_FIRESTORE_WEBSOCKET_PORT=$((9150 + off))
  export TMPDIR="/Users/Shared/tashil-ci/tmp/slot-$k/"
  mkdir -p "$TMPDIR" 2>/dev/null && chmod 1777 "$TMPDIR" 2>/dev/null || true
}

OWN_LEASE=""
cleanup() {
  if [[ -n "$OWN_LEASE" ]]; then
    ci_lease_release slot "$OWN_LEASE"
  fi
}
trap cleanup EXIT

if ci_job_needs_emulator "$JOB"; then
  if [[ -z "${CI_SLOT:-}" ]]; then
    OWN_LEASE="$(ci_lease_acquire slot "${CI_SLOTS:-3}" "${CI_SLOT_WAIT:-1800}" \
      "$JOB@$(git rev-parse --short HEAD 2>/dev/null || echo '?')")"
    CI_SLOT="$OWN_LEASE"
  fi
  ci_slot_env "$CI_SLOT"
  echo "run_job: $JOB on slot $CI_SLOT (firestore :$LOCAL_CI_FIRESTORE_PORT)"
else
  echo "run_job: $JOB"
fi

"job_$JOB"
