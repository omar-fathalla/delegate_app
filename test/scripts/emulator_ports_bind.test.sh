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

export LOCAL_CI_FIRESTORE_PORT=18080
export LOCAL_CI_FIRESTORE_HUB_PORT=14400
export LOCAL_CI_AUTH_PORT=19099
export LOCAL_CI_STORAGE_PORT=19199
export LOCAL_CI_FUNCTIONS_PORT=15001
export LOCAL_CI_LOGGING_PORT=14500
export LOCAL_CI_FIRESTORE_WEBSOCKET_PORT=19150
emulator_export_hosts

if [[ "${FIRESTORE_EMULATOR_HOST}" != "127.0.0.1:18080" ]]; then
  echo "FIRESTORE_EMULATOR_HOST=${FIRESTORE_EMULATOR_HOST} (expected 127.0.0.1:18080)" >&2
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
    if (want!=='127.0.0.1:18080') {
      console.error('inside exec FIRESTORE_EMULATOR_HOST=', want);
      process.exit(1);
    }
    if (process.env.FIRESTORE_EMULATOR_WEBSOCKET_PORT!=='19150') {
      console.error('websocket port env', process.env.FIRESTORE_EMULATOR_WEBSOCKET_PORT);
      process.exit(1);
    }
    execSync('lsof -nP -iTCP:18080 -sTCP:LISTEN', {stdio:'inherit'});
    execSync('lsof -nP -iTCP:19150 -sTCP:LISTEN', {stdio:'inherit'});
    console.log('ok: firestore emulator listening on 18080 (ws 19150)');
  \""

echo "ok: emulator port override bind test passed"