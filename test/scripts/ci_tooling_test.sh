#!/usr/bin/env bash
# Self-test for scripts/ci (jobs, leases, path selection) + drift guard for ci.yml.
# Runs in ios-guards. bash 3.2 compatible.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
# shellcheck source=../../scripts/ci/jobs.sh
source scripts/ci/jobs.sh

fail() { echo "FAIL ci_tooling_test: $*" >&2; exit 1; }

# 1. Every GitHub job has a body and a timeout in jobs.sh.
# TAS-194: ci.yml keeps its inline commands for now. It runs on GitHub-hosted
# ubuntu runners while the repo is public (TAS-178), and run_job.sh is
# Mac-only (slot leases, TMPDIR under /Users/Shared). Keep the job bodies in
# jobs.sh in step with ci.yml by hand until ci.yml moves to run_job.sh.
for j in $CI_JOBS_GITHUB; do
  [[ "$(ci_job_timeout "$j")" -gt 0 ]] || fail "no timeout for job '$j'"
  declare -F "job_$j" >/dev/null || fail "no function job_$j"
done
grep -q -- '--exclude-tags golden' .github/workflows/ci.yml \
  && ! declare -f job_test | grep -q -- '--exclude-tags golden' \
  && fail "ci.yml skips golden tests but job_test in jobs.sh does not"

# 2. Every rules suite in package.json is picked up.
n_pkg="$(node -e 'const s=require("./package.json").scripts;console.log(Object.keys(s).filter(k=>/^test:rules(:|$)/.test(k)).length)')"
n_ci="$(ci_rules_scripts | grep -c .)"
[[ "$n_pkg" == "$n_ci" && "$n_ci" -gt 0 ]] || fail "rules scripts: package.json=$n_pkg ci=$n_ci"

# 3. Change-based selection.
got="$(printf 'firestore.rules\n' | ci_jobs_for_paths)"
[[ "$got" == "ios-guards android-guards rules" ]] || fail "rules-only change -> '$got'"
got="$(printf 'lib/main.dart\n' | ci_jobs_for_paths)"
[[ "$got" == "analyze test build-web ios-guards android-guards" ]] || fail "lib change -> '$got'"
got="$(printf '.github/workflows/ci.yml\n' | ci_jobs_for_paths)"
[[ "$got" == "$CI_JOBS_GITHUB" ]] || fail "workflow change -> '$got'"
got="$(printf 'test/rules/x.test.js\n' | ci_jobs_for_paths)"
[[ "$got" == "ios-guards android-guards rules" ]] || fail "rules test change ran Flutter jobs -> '$got'"
got="$(printf 'docs/x.md\n' | ci_jobs_for_paths)"
[[ "$got" == "ios-guards android-guards" ]] || fail "docs change -> '$got'"
# ci_changes.sh --all is every GitHub job.
[[ "$(bash scripts/ci/ci_changes.sh --all)" == " $CI_JOBS_GITHUB " ]] || fail "ci_changes --all is not every GitHub job"

# 4. Leases: distinct slots, full pool fails fast, dead owner is reaped.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export CI_LEASE_ROOT="$tmp/leases"
# shellcheck source=../../scripts/ci/lease.sh
source scripts/ci/lease.sh
a="$(CI_LEASE_PID=$$ ci_lease_acquire slot 2 0 t1)"
b="$(CI_LEASE_PID=$$ ci_lease_acquire slot 2 0 t2)"
[[ "$a" != "$b" ]] || fail "two leases got the same slot $a"
if CI_LEASE_PID=$$ ci_lease_acquire slot 2 0 t3 2>/dev/null; then fail "third lease on a pool of 2 succeeded"; fi
# Fake a dead owner on slot $b.
printf '%s %s %s %s\n' 999999 test "$(date +%s)" dead >"$CI_LEASE_ROOT/slot/$b/owner"
c="$(CI_LEASE_PID=$$ ci_lease_acquire slot 2 0 t4)"
[[ "$c" == "$b" ]] || fail "stale lease not reaped (got '$c', want '$b')"
# Release only by owner.
CI_LEASE_PID=1 ci_lease_release slot "$a"
[[ -d "$CI_LEASE_ROOT/slot/$a" ]] || fail "lease released by a non-owner"
CI_LEASE_PID=$$ ci_lease_release slot "$a"
[[ ! -d "$CI_LEASE_ROOT/slot/$a" ]] || fail "owner could not release lease"

# TAS-200: CDN warm-up script used after web deploys.
bash test/scripts/warm_web_cdn.test.sh

echo "OK test/scripts/ci_tooling_test.sh"
