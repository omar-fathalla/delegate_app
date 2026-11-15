#!/usr/bin/env bash
# Run firebase emulators:exec with generated config + emulator host env (TA-39).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/scripts/emulator_ports.env.sh"
emulator_export_hosts

CFG="$(mktemp "$ROOT/firebase-emulator-XXXXXX.json")"
trap 'rm -f "$CFG"' EXIT
node "$ROOT/scripts/generate_emulator_firebase_config.js" "$CFG"

FB_TOOLS="${FIREBASE_TOOLS_BIN:-npx --yes firebase-tools@14.15.1}"
# shellcheck disable=SC2086
$FB_TOOLS emulators:exec --config "$CFG" "$@"