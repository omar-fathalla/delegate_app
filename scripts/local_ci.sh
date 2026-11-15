#!/usr/bin/env bash
# Local mirror of .github/workflows/ci.yml for the Mac (tashil-delegate-mac
# machine), used when GitHub Actions cannot schedule jobs (e.g. billing lock).
# Flutter version: 3.44.5 (same as repo .fvmrc and CI flutter-version).
# Does not talk to the runner service, release workflows, or tashil-ci / tashil-mac.
#
# Usage:
#   bash scripts/local_ci.sh <git-sha>
#
# Emulator port overrides (TA-39, e.g. parallel local runs):
#   LOCAL_CI_FIRESTORE_PORT=18080 LOCAL_CI_FIRESTORE_HUB_PORT=14400 bash scripts/local_ci.sh <sha>
#
# Creates a fresh detached worktree at the SHA, runs every CI job plus an
# Android dev debug APK build, and writes logs + SUMMARY.md to
#   /tmp/local-ci/<sha>/
# Timestamps are Africa/Cairo.
set -u
set -o pipefail

CLEAN_PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export PATH="$CLEAN_PATH"
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export TZ=Africa/Cairo
export PUB_ENVIRONMENT="${PUB_ENVIRONMENT:-flutter_bot}"

FLUTTER_SDK="${LOCAL_CI_FLUTTER_SDK:-$HOME/toolchains/flutter-3.44.5}"
NODE22_BIN="${LOCAL_CI_NODE22_BIN:-/Users/delegate-ci/actions-runner/_work/_tool/node/22.23.4/arm64/bin}"
LOCAL_CI_FIRESTORE_PORT="${LOCAL_CI_FIRESTORE_PORT:-8080}"
LOCAL_CI_FIRESTORE_HUB_PORT="${LOCAL_CI_FIRESTORE_HUB_PORT:-4400}"
export LOCAL_CI_FIRESTORE_PORT LOCAL_CI_FIRESTORE_HUB_PORT

if [[ ! -x "$FLUTTER_SDK/bin/flutter" ]]; then
  echo "local_ci: ERROR: Flutter 3.44.5 not found at $FLUTTER_SDK" >&2
  echo "Set LOCAL_CI_FLUTTER_SDK to a 3.44.5 SDK." >&2
  exit 2
fi
if [[ ! -x "$NODE22_BIN/node" ]]; then
  echo "local_ci: ERROR: Node 22 not found at $NODE22_BIN" >&2
  echo "Set LOCAL_CI_NODE22_BIN." >&2
  exit 2
fi

export PATH="$FLUTTER_SDK/bin:$NODE22_BIN:$CLEAN_PATH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ $# -lt 1 || -z "${1:-}" ]]; then
  echo "Usage: bash scripts/local_ci.sh <git-sha>" >&2
  exit 2
fi

cd "$REPO_ROOT"
git fetch origin --quiet || true
if ! SHA="$(git rev-parse --verify "${1}^{commit}" 2>/dev/null)"; then
  git fetch origin "$1" --quiet || git fetch origin +"$1" --quiet || true
  SHA="$(git rev-parse --verify "${1}^{commit}")"
fi

OUT="/tmp/local-ci/${SHA}"
SRC="$OUT/src"
LOGS="$OUT/logs"
mkdir -p "$LOGS"
rm -f "$OUT/SUMMARY.md" "$OUT/results.tsv" "$OUT/full.log"

now() { date '+%Y-%m-%d %H:%M:%S %Z'; }
START_TS="$(now)"
START_EPOCH="$(date +%s)"

{
  echo "local_ci start $START_TS"
  echo "SHA=$SHA"
  echo "flutter: $($FLUTTER_SDK/bin/flutter --version 2>/dev/null | head -1)"
  echo "node: $($NODE22_BIN/node --version)  npm: $($NODE22_BIN/npm --version)"
  echo "java: $(java -version 2>&1 | head -1)"
} | tee "$OUT/full.log"

# Fresh detached worktree. Drop a leftover from a previous run of this SHA.
if git worktree list --porcelain | grep -q "^worktree $SRC\$"; then
  git worktree remove --force "$SRC" || true
fi
rm -rf "$SRC"
git worktree add --detach "$SRC" "$SHA" >>"$OUT/full.log" 2>&1

# Gitignored Android maps/SDK keys, never printed or committed.
seed_local_properties() {
  local dest="$SRC/android/local.properties"
  local cand
  for cand in \
    "$REPO_ROOT/android/local.properties" \
    "$HOME/Development/SwitchPoint/delegate_app/android/local.properties" \
    /tmp/build-ce97cb3/android/local.properties \
    /tmp/build-f7dbcf37/android/local.properties \
    "$HOME/tashil-exports/android/local.properties"
  do
    if [[ -f "$cand" ]] && grep -q '^devMapsAndroidKey=' "$cand" 2>/dev/null; then
      cp "$cand" "$dest"
      echo "seeded android/local.properties from a gitignored local file (key names only, values not logged)" >>"$OUT/full.log"
      return 0
    fi
  done
  echo "warning: no local.properties with devMapsAndroidKey found; android-dev-build may fail" >>"$OUT/full.log"
}

seed_local_properties

# Record a clean checkout at the exact SHA *before* jobs (gitignored
# android/local.properties is not shown by status --porcelain).
WORKTREE_HEAD="$(git -C "$SRC" rev-parse HEAD)"
WORKTREE_STATUS="$(git -C "$SRC" status --porcelain || true)"
{
  echo "worktree HEAD=${WORKTREE_HEAD}"
  if [[ -z "${WORKTREE_STATUS}" ]]; then
    echo "git status --porcelain: (empty)"
  else
    echo "git status --porcelain:"
    printf '%s\n' "${WORKTREE_STATUS}"
  fi
} | tee -a "$OUT/full.log"

# Wait for firestore/auth emulator ports to be free after a previous job.
wait_emulator_ports() {
  local i
  for i in 1 2 3 4 5 6 7 8; do
    if ! lsof -nP -iTCP:"${LOCAL_CI_FIRESTORE_PORT}" -sTCP:LISTEN >/dev/null 2>&1 \
      && ! lsof -nP -iTCP:"${LOCAL_CI_FIRESTORE_HUB_PORT}" -sTCP:LISTEN >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  return 0
}

run_job() {
  local slug="$1"
  local minutes="$2"
  shift 2
  local log="$LOGS/${slug}.log"
  local start_human start_e end_e rc duration
  start_human="$(now)"
  start_e="$(date +%s)"
  echo "===== JOB ${slug} start ${start_human} (timeout ${minutes}m) =====" | tee -a "$log" "$OUT/full.log"
  set +e
  (
    cd "$SRC" || exit 1
    # -c, not -lc: a login shell resets PATH and picks Homebrew Flutter
    # 3.41.2 over the intended $FLUTTER_SDK (3.44.5), which breaks
    # `flutter pub get --enforce-lockfile`.
    timeout --kill-after=30s "${minutes}m" bash -c "$*"
  ) >>"$log" 2>&1
  rc=$?
  end_e="$(date +%s)"
  duration=$((end_e - start_e))
  local result
  if [[ $rc -eq 0 ]]; then
    result=PASS
  elif [[ $rc -eq 124 || $rc -eq 137 ]]; then
    result=TIMEOUT
  else
    result=FAIL
  fi
  echo "===== JOB ${slug} ${result} rc=${rc} duration=${duration}s end $(now) =====" | tee -a "$log" "$OUT/full.log"
  printf '%s\t%s\t%s\t%s\t%s\n' "$slug" "$result" "$rc" "$duration" "$start_human" >>"$OUT/results.tsv"
  return 0
}

# --- jobs, same commands and timeouts as .github/workflows/ci.yml ---

run_job analyze 20 'flutter pub get --enforce-lockfile && flutter analyze --no-fatal-warnings --no-fatal-infos'

run_job test 30 'flutter pub get --enforce-lockfile && flutter test --concurrency=1'

wait_emulator_ports
run_job p0-scripts 15 'cd functions && npm ci && npx --yes firebase-tools@14.15.1 emulators:exec --only auth,firestore --project demo-p0-scripts "node --test scripts/p0-scripts.emulator.test.js"'

run_job build-web 30 'flutter pub get --enforce-lockfile && flutter build web --release'

run_job ios-dev-config-check 5 'bash scripts/ios_dev_config_check.sh && bash scripts/maestro_check_flow_headers.sh && bash scripts/patrol_check_integration_targets.sh && bash scripts/holds_authority_mode_trap_test.sh && python3 scripts/holds_authority_mode_payload_test.py'

wait_emulator_ports
run_job functions 15 'cd functions && npm ci && npm run lint && npm test --if-present && cd .. && npm install --no-audit --no-fund && npm run test:e2e:staff'

wait_emulator_ports
run_job rules 20 'npm install --no-audit --no-fund && npm --prefix functions ci && npm run test:rules && npm run test:rules:interim && npm run test:rules:p0 && npm run test:rules:adv && npm run test:rules:docs && npm run test:rules:subs && npm run test:rules:qa-hold && npm run test:rules:profile && npm run test:rules:m31 && npm run test:rules:source && npm run test:rules:gaps && npm run test:rules:status-guards && npm run test:rules:security && npm run test:rules:ut-nb && npm run test:rules:paymob-superseded && npm run test:rules:privileged-reupload && npm run test:rules:storage && npm run test:e2e:subscriptions && npm run test:e2e:delegate && npm run test:e2e:supervisor-reupload && npm run test:e2e:privileged-reupload'

# Extra vs ci.yml: Android dev debug APK (requested for local machine CI).
run_job android-dev-build 30 "flutter pub get --enforce-lockfile && flutter build apk --debug --flavor dev --dart-define=ENV=dev --dart-define=GIT_SHA=${SHA}"

END_TS="$(now)"
END_EPOCH="$(date +%s)"
TOTAL=$((END_EPOCH - START_EPOCH))

# Remove the worktree; keep logs and the summary.
git worktree remove --force "$SRC" >/dev/null 2>&1 || rm -rf "$SRC"
git worktree prune >/dev/null 2>&1 || true

overall=PASS
fail_count=0
pass_count=0
while IFS=$'\t' read -r slug result rc duration start_human; do
  if [[ "$result" == PASS ]]; then
    pass_count=$((pass_count + 1))
  else
    fail_count=$((fail_count + 1))
    overall=FAIL
  fi
done <"$OUT/results.tsv"

{
  echo "# Local CI summary"
  echo
  echo "- SHA: \`${SHA}\`"
  echo "- Worktree HEAD: \`${WORKTREE_HEAD}\`"
  if [[ -z "${WORKTREE_STATUS:-}" ]]; then
    echo "- git status --porcelain: empty"
  else
    echo "- git status --porcelain:"
    echo
    echo '```'
    printf '%s\n' "${WORKTREE_STATUS}"
    echo '```'
  fi
  echo "- Started: ${START_TS}"
  echo "- Finished: ${END_TS}"
  echo "- Duration: ${TOTAL}s"
  echo "- Host: local Mac (tashil-delegate-mac machine, not GitHub Actions, runner service untouched)"
  echo "- Flutter: \`$($FLUTTER_SDK/bin/flutter --version 2>/dev/null | head -1)\`"
  echo "- Node: \`$($NODE22_BIN/node --version)\`"
  echo "- Java: \`$(java -version 2>&1 | head -1)\`"
  echo "- Overall: **${overall}** (${pass_count} passed, ${fail_count} failed)"
  echo
  echo "Jobs follow \`.github/workflows/ci.yml\`. \`android-dev-build\` is extra (not in that workflow)."
  echo
  echo "| Job | Result | Exit | Duration | Started |"
  echo "| --- | --- | ---: | ---: | --- |"
  while IFS=$'\t' read -r slug result rc duration start_human; do
    echo "| ${slug} | ${result} | ${rc} | ${duration}s | ${start_human} |"
  done <"$OUT/results.tsv"
  echo
  echo "Logs: \`${LOGS}\`"
} >"$OUT/SUMMARY.md"

echo
cat "$OUT/SUMMARY.md"
if [[ "$overall" == PASS ]]; then
  exit 0
fi
exit 1
