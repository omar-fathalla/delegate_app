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
