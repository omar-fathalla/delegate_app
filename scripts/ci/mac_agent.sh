#!/usr/bin/env bash
# Mac CI agent: one pass every 10 minutes (LaunchAgent, scripts/ci/install_mac_agent.sh).
#
#  1. Health: notifies when a delegate_app runner has been offline > 15 min,
#     and again when it is back.
#  2. After each merge: when origin/dev moves, runs the mac-gate job on the new
#     SHA (local_ci.sh --jobs mac-gate --post-status) -> commit status local-ci/mac-gate.
#  3. Nightly (first pass after 00:30 Cairo): full local_ci.sh on origin/dev
#     (--no-apk --post-status), then scripts/ci/cleanup.sh.
#
# Runs as the logged-in developer (fathalla): that account has the simulators,
# Android SDK, Maestro, Patrol, the Maps key and ~/.tashil-ci.env.
# Env: TASHIL_CI_REPO (repo checkout to run from), TASHIL_CI_STATE (state dir),
#      MAC_AGENT_ONLY=health|gate|nightly (one part, for testing).
set -uo pipefail

REPO="${TASHIL_CI_REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
STATE="${TASHIL_CI_STATE:-/Users/Shared/tashil-ci/state}"
GH_REPO="omar-fathalla/delegate_app"
OFFLINE_ALERT_SEC=900
export TZ=Africa/Cairo
mkdir -p "$STATE"
LOG="$STATE/mac_agent.log"

log() { echo "$(date '+%F %T') $*" >>"$LOG"; }
notify() {
  log "NOTIFY: $1"
  osascript -e "display notification \"${1//\"/\'}\" with title \"Tashil CI\"" >/dev/null 2>&1 || true
}
want() { [[ -z "${MAC_AGENT_ONLY:-}" || "$MAC_AGENT_ONLY" == "$1" ]]; }

# --- 1. runner health --------------------------------------------------------
health() {
  local rows name status f since now
  rows="$(gh api "repos/${GH_REPO}/actions/runners" -q '.runners[] | select(.labels[].name=="delegate-app") | "\(.name) \(.status)"' 2>/dev/null | sort -u)" \
    || { log "health: gh api failed"; return 0; }
  now="$(date +%s)"
  while read -r name status; do
    [[ -n "$name" ]] || continue
    f="$STATE/offline-$name"
    if [[ "$status" == online ]]; then
      if [[ -f "$f.alerted" ]]; then notify "Runner $name is back online"; fi
      rm -f "$f" "$f.alerted"
    else
      [[ -f "$f" ]] || echo "$now" >"$f"
      since="$(cat "$f")"
      if (( now - since > OFFLINE_ALERT_SEC )) && [[ ! -f "$f.alerted" ]]; then
        notify "Runner $name offline for $(( (now - since) / 60 )) min. Check: sudo launchctl print system/actions.runner.${GH_REPO/\//-}.$name"
        touch "$f.alerted"
      fi
    fi
  done <<<"$rows"
}

# --- 2. mac-gate after each merge to dev ------------------------------------
gate() {
  git -C "$REPO" fetch origin dev --quiet || { log "gate: fetch failed"; return 0; }
  local sha last
  sha="$(git -C "$REPO" rev-parse origin/dev)"
  last="$(cat "$STATE/last-gated-dev" 2>/dev/null || true)"
  [[ "$sha" != "$last" ]] || return 0
  echo "$sha" >"$STATE/last-gated-dev"   # record first: a failing gate is not retried every 10 min
  log "gate: running mac-gate on dev ${sha:0:8}"
  if bash "$REPO/scripts/local_ci.sh" --jobs mac-gate --post-status "$sha" >>"$LOG" 2>&1; then
    log "gate: PASS ${sha:0:8}"
  else
    notify "mac-gate FAILED on dev ${sha:0:8}. Summary: /tmp/local-ci.noindex/${sha}/SUMMARY.md"
  fi
}

# --- 3. nightly --------------------------------------------------------------
nightly() {
  local today hm sha
  today="$(date +%F)"
  hm="$(date +%H%M)"
  [[ "$(cat "$STATE/last-nightly" 2>/dev/null || true)" != "$today" ]] || return 0
  (( 10#$hm >= 30 && 10#$hm < 600 )) || return 0
  echo "$today" >"$STATE/last-nightly"
  git -C "$REPO" fetch origin dev --quiet || true
  sha="$(git -C "$REPO" rev-parse origin/dev)"
  log "nightly: full local_ci on dev ${sha:0:8}"
  if ! bash "$REPO/scripts/local_ci.sh" --no-apk --post-status "$sha" >>"$LOG" 2>&1; then
    notify "Nightly CI FAILED on dev ${sha:0:8}. Summary: /tmp/local-ci.noindex/${sha}/SUMMARY.md"
  fi
  bash "$REPO/scripts/ci/cleanup.sh" >>"$LOG" 2>&1 || true
}

want health && health
want gate && gate
want nightly && nightly
# Keep the agent log small.
if [[ -f "$LOG" ]] && (( $(wc -l <"$LOG") > 5000 )); then
  tail -n 5000 "$LOG" >"$LOG.tmp" && mv "$LOG.tmp" "$LOG"
fi
exit 0
