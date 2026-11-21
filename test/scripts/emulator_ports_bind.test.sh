#!/usr/bin/env bash
# TA-39: prove LOCAL_CI_* ports are passed to emulators:exec and bind (not grep-only).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

# shellcheck disable=SC1091
source "$ROOT/scripts/emulator_ports.env.sh"

_cfg_base="$(mktemp "${TMPDIR:-/tmp}/emulator-default-ports.XXXXXX")"
CFG_DEFAULT="${_cfg_base}.json"
mv "${_cfg_base}" "${CFG_DEFAULT}"
trap 'rm -f "$CFG_DEFAULT"' EXIT

LOCAL_CI_ENV_UNSET=(
  -u LOCAL_CI_FIRESTORE_PORT
  -u LOCAL_CI_FIRESTORE_HUB_PORT
  -u LOCAL_CI_AUTH_PORT
  -u LOCAL_CI_STORAGE_PORT
  -u LOCAL_CI_FUNCTIONS_PORT
  -u LOCAL_CI_LOGGING_PORT
  -u LOCAL_CI_FIRESTORE_WEBSOCKET_PORT
)

# Default-port assertion: clean env so inherited local_ci overrides do not skew generation.
env "${LOCAL_CI_ENV_UNSET[@]}" node "$ROOT/scripts/generate_emulator_firebase_config.js" "$CFG_DEFAULT"
env "${LOCAL_CI_ENV_UNSET[@]}" node -e "
const fs=require('fs');
const j=JSON.parse(fs.readFileSync('${CFG_DEFAULT}','utf8'));
const e=j.emulators;
const want={firestore:8080,hub:4400,auth:9099,storage:9199,functions:5001,logging:4500};
for (const [k,p] of Object.entries(want)) {
  if (e[k].port !== p) {
    console.error('default port mismatch', k, e[k].port, 'want', p);
    process.exit(1);
  }
}
if (e.firestore.websocketPort !== 9150) {
  console.error('default websocket mismatch', e.firestore.websocketPort, 'want', 9150);
  process.exit(1);
}
console.log('ok: default generated emulator ports match firebase.json behavior');
"

# TAS-107: never a fixed port set (18080 was shared by every P0 job and local
# run on the Mac). CI uses this runner's slot; locally the first free slot.
if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
  emulator_use_slot 20000 "$(emulator_runner_slot "${RUNNER_NAME:-}")"
else
  emulator_pick_local_slot || { echo "no free local emulator slot" >&2; emulator_ports_busy_report >&2; exit 1; }
fi
FS_PORT="${LOCAL_CI_FIRESTORE_PORT}"
WS_PORT="${LOCAL_CI_FIRESTORE_WEBSOCKET_PORT}"
if [[ "${FS_PORT}" == 8080 ]]; then
  echo "bind test must run on a non-default port, got ${FS_PORT}" >&2
  exit 1
fi
emulator_export_hosts

if [[ "${FIRESTORE_EMULATOR_HOST}" != "127.0.0.1:${FS_PORT}" ]]; then
  echo "FIRESTORE_EMULATOR_HOST=${FIRESTORE_EMULATOR_HOST} (expected 127.0.0.1:${FS_PORT})" >&2
  exit 1
fi

wait_emulator_ports_free || { echo "slot ports busy:" >&2; emulator_ports_busy_report >&2; exit 1; }

# Short-lived firestore emulator on non-default port; assert listen + env inside exec.
bash "$ROOT/scripts/emulators_exec.sh" \
  --only firestore \
  --project demo-emulator-port-bind \
  "node -e \"
    const {execSync}=require('child_process');
    const want=process.env.FIRESTORE_EMULATOR_HOST;
    if (want!=='127.0.0.1:${FS_PORT}') {
      console.error('inside exec FIRESTORE_EMULATOR_HOST=', want);
      process.exit(1);
    }
    if (process.env.FIRESTORE_EMULATOR_WEBSOCKET_PORT!=='${WS_PORT}') {
      console.error('websocket port env', process.env.FIRESTORE_EMULATOR_WEBSOCKET_PORT);
      process.exit(1);
    }
    execSync('lsof -nP -iTCP:${FS_PORT} -sTCP:LISTEN', {stdio:'inherit'});
    execSync('lsof -nP -iTCP:${WS_PORT} -sTCP:LISTEN', {stdio:'inherit'});
    console.log('ok: firestore emulator listening on ${FS_PORT} (ws ${WS_PORT})');
  \""

echo "ok: emulator port override bind test passed"