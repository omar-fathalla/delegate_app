#!/usr/bin/env bash
# TA-39: prove LOCAL_CI_* ports are passed to emulators:exec and bind (not grep-only).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

# shellcheck disable=SC1091
source "$ROOT/scripts/emulator_ports.env.sh"

CFG_DEFAULT="$(mktemp)"
trap 'rm -f "$CFG_DEFAULT"' EXIT
node "$ROOT/scripts/generate_emulator_firebase_config.js" "$CFG_DEFAULT"
node -e "
const fs=require('fs');
const j=JSON.parse(fs.readFileSync('${CFG_DEFAULT}','utf8'));
const e=j.emulators;
const want={firestore:8080,hub:4400,auth:9099,storage:9199,functions:5001};
for (const [k,p] of Object.entries(want)) {
  if (e[k].port !== p) {
    console.error('default port mismatch', k, e[k].port, 'want', p);
    process.exit(1);
  }
}
console.log('ok: default generated emulator ports match firebase.json behavior');
"

export LOCAL_CI_FIRESTORE_PORT=18080
export LOCAL_CI_FIRESTORE_HUB_PORT=14400
export LOCAL_CI_AUTH_PORT=19099
export LOCAL_CI_STORAGE_PORT=19199
export LOCAL_CI_FUNCTIONS_PORT=15001
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
    execSync('lsof -nP -iTCP:18080 -sTCP:LISTEN', {stdio:'inherit'});
    console.log('ok: firestore emulator listening on 18080');
  \""

echo "ok: emulator port override bind test passed"