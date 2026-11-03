#!/usr/bin/env bash
# Local-only: start Firebase emulators (Auth, Firestore, Functions, Storage)
# with the candidate rules, seed FAKE test data, then keep running.
# Never touches production: project is demo-tashil-local (demo-* = offline only).
#
#   scripts/local_rules_test.sh            # phase 1b rules (default)
#   RULES=phase1 scripts/local_rules_test.sh
#   RULES=deployed scripts/local_rules_test.sh   # compare against current prod rules
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)
PROJECT=demo-tashil-local
RULES=${RULES:-phase1b}
case "$RULES" in
  phase1b) RULES_FILE=firestore.rules.phase1b ;;
  phase1)  RULES_FILE=firestore.rules.phase1 ;;
  deployed) RULES_FILE=firestore.rules.deployed ;;
  *) echo "RULES must be phase1b | phase1 | deployed"; exit 1 ;;
esac
[ -f "$RULES_FILE" ] || { echo "missing $RULES_FILE"; exit 1; }

CONFIG=firebase.local.gen.json
sed "s#\"firestore.rules.phase1b\"#\"$RULES_FILE\"#" firebase.local.json > "$CONFIG"

echo "==> functions: install + build"
( cd functions && { [ -d node_modules ] || { [ -f package-lock.json ] && npm ci --no-audit --no-fund || npm install --no-audit --no-fund; }; } && npm run build >/dev/null )
# Emulator-only quirk: inside the Functions emulator admin.firestore.Timestamp /
# FieldValue are undefined. Patch the BUILD OUTPUT (functions/lib, gitignored,
# rebuilt by every deploy) to import them from firebase-admin/firestore.
# Source code is not changed.
sed -i.bak -E 's/admin\.firestore\.(Timestamp|FieldValue)/require("firebase-admin\/firestore").\1/g' functions/lib/*.js && rm -f functions/lib/*.js.bak
echo "==> seed deps"
( cd scripts/local && { [ -d node_modules ] || npm install --no-audit --no-fund --silent; } )

export FIRESTORE_EMULATOR_HOST=127.0.0.1:8080
export FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099
export GCLOUD_PROJECT=$PROJECT

echo "==> starting emulators with $RULES_FILE (project $PROJECT)"
firebase emulators:start --project "$PROJECT" --config "$CONFIG" > /tmp/tashil-emulators.log 2>&1 &
EMU_PID=$!
trap 'echo "==> stopping emulators"; kill $EMU_PID 2>/dev/null; wait $EMU_PID 2>/dev/null; rm -f "$ROOT/$CONFIG"' EXIT INT TERM

for i in $(seq 1 90); do
  if grep -q "All emulators ready" /tmp/tashil-emulators.log; then break; fi
  if ! kill -0 $EMU_PID 2>/dev/null; then cat /tmp/tashil-emulators.log; exit 1; fi
  sleep 2
done
grep -q "All emulators ready" /tmp/tashil-emulators.log || { tail -40 /tmp/tashil-emulators.log; exit 1; }
grep -E "functions\[.*(delegateLoginV2|staffPhoneLookup)" /tmp/tashil-emulators.log | sed 's/^/   /' || true

echo "==> seeding fake data"
node scripts/local/seed.mjs

cat <<MSG

Emulators running (UI: http://127.0.0.1:4000, log: /tmp/tashil-emulators.log).
Rules: $RULES_FILE

Run the app against them in another terminal:
  flutter run -d chrome --dart-define=USE_FIREBASE_EMULATOR=true
  flutter run -d macos  --dart-define=USE_FIREBASE_EMULATOR=true
  flutter run -d "iPhone 16" --dart-define=USE_FIREBASE_EMULATOR=true   # iOS simulator
  (Android emulator: add --dart-define=EMULATOR_HOST=10.0.2.2)

Rules denials show in the Emulator UI > Firestore > Requests.
Press Ctrl+C to stop.
MSG
[ "${NO_WAIT:-}" = "1" ] && exit 0
wait $EMU_PID
