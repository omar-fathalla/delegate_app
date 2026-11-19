#!/usr/bin/env bash
# iOS simulator pool for device jobs (mac-gate). Each job leases one simulator
# named Tashil-CI-<n>; it is created on first use, booted on lease and shut down
# on release ("boot when needed, shut down when finished").
#
#   source scripts/ci/lease.sh; source scripts/ci/devices.sh
#   ci_ios_sim_acquire "mac-gate@abc123"   # sets CI_SIM_N, CI_SIM_UDID
#   ...
#   ci_ios_sim_release
#
# Env: CI_IOS_SIMS (pool size, default 2), CI_IOS_SIM_TYPE (default "iPhone 17"),
#      CI_DEVICE_WAIT (seconds, default 3600). bash 3.2 compatible.

CI_IOS_SIMS="${CI_IOS_SIMS:-2}"
CI_IOS_SIM_TYPE="${CI_IOS_SIM_TYPE:-iPhone 17}"

_ci_latest_ios_runtime() {
  xcrun simctl list runtimes available 2>/dev/null \
    | sed -nE 's/^iOS [0-9.]+ .* - (com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9-]+)$/\1/p' \
    | tail -1
}

_ci_sim_udid_by_name() {
  xcrun simctl list devices available 2>/dev/null \
    | sed -nE "s/^ +$1 \(([0-9A-F-]{36})\).*/\1/p" | head -1
}

ci_ios_sim_acquire() {
  local label="${1:-device-job}" n udid runtime
  n="$(ci_lease_acquire ios-sim "$CI_IOS_SIMS" "${CI_DEVICE_WAIT:-3600}" "$label")" || return 1
  udid="$(_ci_sim_udid_by_name "Tashil-CI-$n")"
  if [[ -z "$udid" ]]; then
    runtime="$(_ci_latest_ios_runtime)"
    [[ -n "$runtime" ]] || { echo "devices: no iOS runtime installed" >&2; ci_lease_release ios-sim "$n"; return 1; }
    udid="$(xcrun simctl create "Tashil-CI-$n" "$CI_IOS_SIM_TYPE" "$runtime")" || {
      ci_lease_release ios-sim "$n"; return 1; }
    echo "devices: created Tashil-CI-$n ($udid, $runtime)" >&2
  fi
  xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || {
    echo "devices: could not boot Tashil-CI-$n ($udid)" >&2
    ci_lease_release ios-sim "$n"
    return 1
  }
  export CI_SIM_N="$n" CI_SIM_UDID="$udid" TASHIL_SIM_UDID="$udid" MAESTRO_DEVICE_ID="$udid"
  echo "devices: leased Tashil-CI-$n ($udid)" >&2
}

ci_ios_sim_release() {
  [[ -n "${CI_SIM_N:-}" ]] || return 0
  xcrun simctl shutdown "$CI_SIM_UDID" >/dev/null 2>&1 || true
  ci_lease_release ios-sim "$CI_SIM_N"
  echo "devices: released Tashil-CI-$CI_SIM_N" >&2
  unset CI_SIM_N CI_SIM_UDID
}
