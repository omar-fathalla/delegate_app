#!/usr/bin/env bash
# TAS-394: every Patrol target gets its own -t, and the ran-targets guard fails
# when a target has no result line. No device or patrol run needed.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
fail() { echo "FAIL patrol_targets_test: $*" >&2; exit 1; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# A stub `patrol` on PATH so the wrapper gets past its CLI check.
mkdir -p "$tmp/bin"; printf '#!/bin/sh\nexit 0\n' >"$tmp/bin/patrol"; chmod +x "$tmp/bin/patrol"

# 1. Dry run: one -t per default target, none bare.
cmd="$(PATH="$tmp/bin:$PATH" PATROL_RUN_DRY=1 PATROL_DEV_SECRET=s3cr3t \
  bash scripts/patrol_run_dev_integration.sh | tail -n 1)"
n_targets="$(sed -n '/^DEFAULT_TARGETS=(/,/^)/p' scripts/patrol_run_dev_integration.sh | grep -c '_test\.dart')"
n_t="$(grep -o -- ' -t patrol_test/[^ ]*_test\.dart' <<<"$cmd" | wc -l | tr -d ' ')"
[[ "$n_targets" -ge 5 ]] || fail "expected >=5 default targets, got $n_targets"
[[ "$n_t" == "$n_targets" ]] || fail "$n_t '-t <file>' pairs for $n_targets targets: $cmd"
grep -q 's3cr3t' <<<"$cmd" && fail "dry run printed the secret"
echo "ok: one -t per target ($n_t)"

# 2. Explicit -t targets keep their own -t too.
cmd="$(PATH="$tmp/bin:$PATH" PATROL_RUN_DRY=1 bash scripts/patrol_run_dev_integration.sh \
  -t patrol_test/integration_native_permissions_test.dart \
  -t patrol_test/integration_push_notification_test.dart | tail -n 1)"
[[ "$(grep -o -- ' -t ' <<<"$cmd" | wc -l | tr -d ' ')" == 2 ]] || fail "explicit targets: $cmd"
echo "ok: explicit targets"

# 3. Guard: all targets reported -> ok; one missing -> exit 1 naming it.
cat >"$tmp/ok.log" <<'LOG'
✅ dev: a (/integration_a_test.dart) (66s)
❌ dev: b [90m(/integration_b_test.dart)[0m
Test summary:
LOG
bash scripts/patrol_check_ran_targets.sh "$tmp/ok.log" \
  patrol_test/integration_a_test.dart patrol_test/integration_b_test.dart >/dev/null \
  || fail "guard rejected a log where every target ran"
if out="$(bash scripts/patrol_check_ran_targets.sh "$tmp/ok.log" \
  patrol_test/integration_a_test.dart patrol_test/integration_c_test.dart 2>&1)"; then
  fail "guard passed with a target that never ran"
fi
grep -q 'integration_c_test.dart' <<<"$out" || fail "guard did not name the missing target: $out"
echo "ok: ran-targets guard"

# 4. A may-skip-on ios file may be absent on iOS when the summary has a skip,
#    but not on Android, and not when nothing was skipped.
printf '// patrol-ran-targets: may-skip-on ios (test)\n' >"$tmp/integration_d_test.dart"
printf '%s\n' '✅ dev: a (/integration_a_test.dart)' '⏩ Skipped: 1' >"$tmp/skip.log"
PATROL_RAN_TARGETS_PLATFORM=ios bash scripts/patrol_check_ran_targets.sh "$tmp/skip.log" \
  patrol_test/integration_a_test.dart "$tmp/integration_d_test.dart" >/dev/null \
  || fail "may-skip file rejected on ios"
PATROL_RAN_TARGETS_PLATFORM=android bash scripts/patrol_check_ran_targets.sh "$tmp/skip.log" \
  patrol_test/integration_a_test.dart "$tmp/integration_d_test.dart" >/dev/null 2>&1 \
  && fail "may-skip-on ios file allowed on android"
printf '%s\n' '✅ dev: a (/integration_a_test.dart)' '⏩ Skipped: 0' >"$tmp/noskip.log"
PATROL_RAN_TARGETS_PLATFORM=ios bash scripts/patrol_check_ran_targets.sh "$tmp/noskip.log" \
  patrol_test/integration_a_test.dart "$tmp/integration_d_test.dart" >/dev/null 2>&1 \
  && fail "may-skip file allowed with zero skips"
# 5. The real gate log shape: many result lines, early match (SIGPIPE case).
{ for i in $(seq 1 3000); do echo "✅ $i. tap (native)"; done
  echo '✅ dev: a (/integration_a_test.dart)'
  for i in $(seq 1 3000); do echo "✅ $i. tap (native)"; done
  echo '✅ dev: b (/integration_b_test.dart)'; } >"$tmp/big.log"
bash scripts/patrol_check_ran_targets.sh "$tmp/big.log" \
  patrol_test/integration_a_test.dart patrol_test/integration_b_test.dart >/dev/null \
  || fail "guard missed a target in a long log"
echo "ok: may-skip + long log"
