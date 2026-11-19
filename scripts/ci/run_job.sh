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
#   CI_SLOTS        number of port slots on this Mac (default 2: each emulator
#                   job runs a Java Firestore emulator; 3 at once overloaded the Mac)
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
  export TMPDIR="/Users/Shared/tashil-ci/tmp.noindex/slot-$k/"
  mkdir -p "$TMPDIR" 2>/dev/null && chmod 1777 "$TMPDIR" 2>/dev/null || true
}

# The Firestore emulator often fails to stop on these runners ("Error stopping
# Firestore Emulator") and keeps listening for a few seconds. The next job on
# the same slot then connects to that dying emulator and its first write hangs
# (P0 scripts: DEADLINE_EXCEEDED after 60 s, run 44448556800). So every
# emulator job frees its slot's ports before it starts and after it ends.
# Slot ports are CI-only (default + k*10000), so only stray emulators live there.
ci_slot_ports() {
  echo "$LOCAL_CI_FIRESTORE_PORT $LOCAL_CI_FIRESTORE_HUB_PORT $LOCAL_CI_AUTH_PORT" \
    "$LOCAL_CI_STORAGE_PORT $LOCAL_CI_FUNCTIONS_PORT $LOCAL_CI_LOGGING_PORT" \
    "$LOCAL_CI_FIRESTORE_WEBSOCKET_PORT"
}
ci_slot_listeners() {
  local port
  for port in $(ci_slot_ports); do
    lsof -nP -t -iTCP:"$port" -sTCP:LISTEN 2>/dev/null || true
  done | sort -u
}
ci_slot_free_ports() {
  local pids i
  pids="$(ci_slot_listeners)"
  [[ -n "$pids" ]] || return 0
  echo "run_job: slot $CI_SLOT ports still in use by pid(s) $(echo $pids), stopping them"
  # shellcheck disable=SC2086
  kill $pids 2>/dev/null || true
  for i in $(seq 1 20); do
    [[ -n "$(ci_slot_listeners)" ]] || return 0
    sleep 0.5
  done
  pids="$(ci_slot_listeners)"
  # shellcheck disable=SC2086
  [[ -z "$pids" ]] || kill -9 $pids 2>/dev/null || true
  sleep 1
  pids="$(ci_slot_listeners)"
  if [[ -n "$pids" ]]; then
    echo "run_job: slot $CI_SLOT ports still held by pid(s) $(echo $pids) (another user?)" >&2
    return 1
  fi
}

OWN_LEASE=""
cleanup() {
  if [[ -n "${CI_SLOT:-}" && -n "${LOCAL_CI_FIRESTORE_PORT:-}" ]]; then
    ci_slot_free_ports || true
  fi
  if [[ -n "$OWN_LEASE" ]]; then
    ci_lease_release slot "$OWN_LEASE"
  fi
}
trap cleanup EXIT

if ci_job_needs_emulator "$JOB"; then
  if [[ -z "${CI_SLOT:-}" ]]; then
    OWN_LEASE="$(ci_lease_acquire slot "${CI_SLOTS:-2}" "${CI_SLOT_WAIT:-1800}" \
      "$JOB@$(git rev-parse --short HEAD 2>/dev/null || echo '?')")"
    CI_SLOT="$OWN_LEASE"
  fi
  ci_slot_env "$CI_SLOT"
  echo "run_job: $JOB on slot $CI_SLOT (firestore :$LOCAL_CI_FIRESTORE_PORT)"
  ci_slot_free_ports
else
  echo "run_job: $JOB"
fi

"job_$JOB"
