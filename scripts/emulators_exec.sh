#!/usr/bin/env bash
# Run firebase emulators:exec with generated config + emulator host env (TA-39).
#
# TAS-107: picks a port slot so CI jobs on the shared Mac runners and local
# sessions never fight over 8080/4400/9099 (see scripts/emulator_ports.env.sh).
#   EMULATOR_PORT_SLOT=off  use the plain LOCAL_CI_* defaults (old behaviour)
#   LOCAL_CI_* set          used as given
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/scripts/emulator_ports.env.sh"

if [[ "${EMULATOR_PORTS_EXPLICIT}" -eq 0 && "${EMULATOR_PORT_SLOT:-auto}" != "off" ]]; then
  if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
    emulator_use_slot 20000 "$(emulator_runner_slot "${RUNNER_NAME:-}")"
  elif ! emulator_pick_local_slot; then
    echo "emulator ports: no free local slot (30000 + 1..9 x 1000). Holders of slot 1:" >&2
    emulator_use_slot 30000 1
    emulator_ports_busy_report >&2
    exit 1
  fi
  echo "emulator ports: slot ${EMULATOR_PORT_SLOT_USED} (firestore ${LOCAL_CI_FIRESTORE_PORT}, hub ${LOCAL_CI_FIRESTORE_HUB_PORT}, auth ${LOCAL_CI_AUTH_PORT})" >&2
fi

# Fail fast with the holder's details instead of firebase's bare "port taken".
if ! emulator_ports_free; then
  # In CI a busy port on our own runner slot can only be a leftover of an
  # earlier cancelled job: clear orphans first.
  if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
    emulator_kill_orphans_on_ports
  fi
  if ! wait_emulator_ports_free; then
    echo "emulator ports busy; another emulator is using them:" >&2
    emulator_ports_busy_report >&2
    echo "Stop it, or set LOCAL_CI_* to other ports (scripts/kill_stale_emulators.sh lists orphans)." >&2
    exit 1
  fi
fi

emulator_export_hosts

_cfg_base="$(mktemp "${TMPDIR:-/tmp}/firebase-emulator.XXXXXX")"
CFG="${_cfg_base}.json"
mv "${_cfg_base}" "${CFG}"
trap 'rm -f "$CFG"' EXIT
node "$ROOT/scripts/generate_emulator_firebase_config.js" "$CFG"

FB_TOOLS="${FIREBASE_TOOLS_BIN:-npx --yes firebase-tools@14.15.1}"
# shellcheck disable=SC2086
$FB_TOOLS emulators:exec --config "$CFG" "$@"
