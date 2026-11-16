#!/usr/bin/env bash
# Run all test:rules:* npm scripts and record pass/total (sequential; wait for emulator ports).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# shellcheck source=scripts/emulator_ports.env.sh
source "$ROOT/scripts/emulator_ports.env.sh"
OUT="${1:-/tmp/rules_matrix.log}"
SUITS=(
  test:rules
  test:rules:interim
  test:rules:invite-claim
  test:rules:p0
  test:rules:adv
  test:rules:docs
  test:rules:subs
  test:rules:qa-hold
  test:rules:profile
  test:rules:m31
  test:rules:source
  test:rules:gaps
  test:rules:status-guards
  test:rules:security
  test:rules:ut-nb
  test:rules:nationalid-scope
  test:rules:users-nationalid-lock
  test:rules:paymob-superseded
  test:rules:privileged-reupload
  test:rules:storage
  test:rules:prod-compat
)
: >"$OUT"
echo "rules matrix @ $(git rev-parse --short HEAD) $(date -Is)" | tee -a "$OUT"
for s in "${SUITS[@]}"; do
  wait_emulator_ports_free || true
  sleep 1
  echo "=== $s ===" | tee -a "$OUT"
  tmp="$(mktemp)"
  if npm run "$s" >"$tmp" 2>&1; then
  status=PASS
  else
  status=FAIL
  fi
  cat "$tmp" >>"$OUT"
  pass=$(grep -E '^# pass ' "$tmp" | tail -1 | awk '{print $3}')
  fail=$(grep -E '^# fail ' "$tmp" | tail -1 | awk '{print $3}')
  total=$(grep -E '^# tests ' "$tmp" | tail -1 | awk '{print $3}')
  rm -f "$tmp"
  echo "RESULT $s ${pass:-?}/${total:-?} $status fail=${fail:-0}" | tee -a "$OUT"
done
echo "LOG=$OUT"