#!/usr/bin/env bash
# Shared leases for CI on one Mac: several GitHub runners, local_ci.sh runs and
# AI agents can hold different slots at once, never the same one.
#
# A lease is a directory (mkdir is atomic) under $CI_LEASE_ROOT/<pool>/<n>
# with an `owner` file: "<pid> <user> <unix-start> <label>".
# A lease is stale (and taken over) when its pid is gone or it is older than
# CI_LEASE_MAX_AGE seconds.
#
#   source scripts/ci/lease.sh
#   n="$(ci_lease_acquire slot 3 900 "rules@abc123")" || exit 1   # waits up to 900 s
#   ...
#   ci_lease_release slot "$n"
#
# bash 3.2 compatible.

CI_LEASE_ROOT="${CI_LEASE_ROOT:-/Users/Shared/tashil-ci/leases}"
CI_LEASE_MAX_AGE="${CI_LEASE_MAX_AGE:-14400}" # 4 h: longer than any job timeout

_ci_lease_dir_init() {
  local pool_dir="$CI_LEASE_ROOT/$1"
  if [[ ! -d "$pool_dir" ]]; then
    mkdir -p "$pool_dir" 2>/dev/null || return 1
  fi
  # Shared between fathalla, delegate-ci and tashil-ci: world-writable + sticky.
  chmod 1777 "$CI_LEASE_ROOT" "$pool_dir" 2>/dev/null || true
  [[ -w "$pool_dir" ]]
}

_ci_lease_alive() {
  # ps works across users (kill -0 does not: EPERM for other users' pids).
  ps -p "$1" >/dev/null 2>&1
}

# Returns 0 if the lease dir is stale and was removed.
_ci_lease_reap_if_stale() {
  local d="$1" pid user started label now
  [[ -d "$d" ]] || return 1
  if ! read -r pid user started label <"$d/owner" 2>/dev/null; then
    # Owner file not written yet: give the creator 10 s.
    local mtime
    mtime="$(stat -f %m "$d" 2>/dev/null || echo 0)"
    now="$(date +%s)"
    if (( now - mtime > 10 )); then
      rm -rf "$d" 2>/dev/null && return 0
    fi
    return 1
  fi
  now="$(date +%s)"
  if ! _ci_lease_alive "$pid" || (( now - started > CI_LEASE_MAX_AGE )); then
    rm -rf "$d" 2>/dev/null && return 0
  fi
  return 1
}

# ci_lease_acquire <pool> <size> <wait-seconds> [label]  -> prints slot number
ci_lease_acquire() {
  local pool="$1" size="$2" wait="${3:-0}" label="${4:-${CI_JOB:-job}}"
  local pid="${CI_LEASE_PID:-$$}"
  _ci_lease_dir_init "$pool" || {
    echo "ci_lease: cannot write $CI_LEASE_ROOT/$pool" >&2
    return 2
  }
  local deadline=$(( $(date +%s) + wait )) n d announced=0
  while :; do
    n=1
    while (( n <= size )); do
      d="$CI_LEASE_ROOT/$pool/$n"
      if mkdir "$d" 2>/dev/null || { _ci_lease_reap_if_stale "$d" && mkdir "$d" 2>/dev/null; }; then
        printf '%s %s %s %s\n' "$pid" "$(id -un)" "$(date +%s)" "$label" >"$d/owner"
        chmod 0777 "$d" 2>/dev/null || true
        echo "$n"
        return 0
      fi
      n=$((n + 1))
    done
    if (( $(date +%s) >= deadline )); then
      echo "ci_lease: no free $pool lease after ${wait}s" >&2
      ci_lease_status "$pool" >&2
      return 1
    fi
    if (( announced == 0 )); then
      echo "ci_lease: all $size $pool leases busy, waiting (max ${wait}s)" >&2
      announced=1
    fi
    sleep 3
  done
}

# ci_lease_release <pool> <n>  (only releases a lease this pid owns)
ci_lease_release() {
  local d="$CI_LEASE_ROOT/$1/$2" pid rest
  local me="${CI_LEASE_PID:-$$}"
  [[ -d "$d" ]] || return 0
  read -r pid rest <"$d/owner" 2>/dev/null || true
  if [[ "$pid" == "$me" ]]; then
    rm -rf "$d"
  fi
}

ci_lease_status() {
  local pool="$1" d pid user started label
  for d in "$CI_LEASE_ROOT/$pool"/*; do
    [[ -d "$d" ]] || continue
    if read -r pid user started label <"$d/owner" 2>/dev/null; then
      echo "  $pool/$(basename "$d"): pid=$pid user=$user age=$(( $(date +%s) - started ))s $label"
    fi
  done
}
