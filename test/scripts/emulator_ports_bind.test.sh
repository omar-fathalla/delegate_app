#!/usr/bin/env bash
# TA-39: prove LOCAL_CI_* ports are passed to emulators:exec and bind (not grep-only).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

# Port offset for the override part: the CI slot's ports when run_job.sh
# leased one (LOCAL_CI_* already set, e.g. slot 2 = 28080), else +10000.
# Hardcoding 18080 made this collide with whatever job held slot 1.
if [[ -n "${LOCAL_CI_FIRESTORE_PORT:-}" && "$LOCAL_CI_FIRESTORE_PORT" != 8080 ]]; then
  PORT_OFF=$(( LOCAL_CI_FIRESTORE_PORT - 8080 ))
else
  PORT_OFF=10000
fi

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

FS_PORT=$(( 8080 + PORT_OFF ))
WS_PORT=$(( 9150 + PORT_OFF ))
export LOCAL_CI_FIRESTORE_PORT=$FS_PORT
export LOCAL_CI_FIRESTORE_HUB_PORT=$(( 4400 + PORT_OFF ))
export LOCAL_CI_AUTH_PORT=$(( 9099 + PORT_OFF ))
export LOCAL_CI_STORAGE_PORT=$(( 9199 + PORT_OFF ))
export LOCAL_CI_FUNCTIONS_PORT=$(( 5001 + PORT_OFF ))
export LOCAL_CI_LOGGING_PORT=$(( 4500 + PORT_OFF ))
export LOCAL_CI_FIRESTORE_WEBSOCKET_PORT=$WS_PORT
emulator_export_hosts

if [[ "${FIRESTORE_EMULATOR_HOST}" != "127.0.0.1:${FS_PORT}" ]]; then
  echo "FIRESTORE_EMULATOR_HOST=${FIRESTORE_EMULATOR_HOST} (expected 127.0.0.1:${FS_PORT})" >&2
  exit 1
fi

wait_emulator_ports_free

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