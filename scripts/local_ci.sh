#!/usr/bin/env bash
# Local mirror of .github/workflows/ci.yml for the Mac (tashil-delegate-mac
# machine), used when GitHub Actions cannot schedule jobs (e.g. billing lock).
# Flutter version: 3.44.5 (same as repo .fvmrc and CI flutter-version).
# Does not talk to the runner service, release workflows, or tashil-ci / tashil-mac.
#
# Usage:
#   bash scripts/local_ci.sh [options] <git-sha>
#     --jobs a,b,c        run only these jobs (see: bash scripts/ci/run_job.sh --list)
#     --changed[=<base>]  run only jobs needed for files changed vs <base> (default origin/dev)
#     --no-apk            skip the local-only android-dev-build job
#     --post-status       publish each job result as a GitHub commit status
#                         (context "local-ci/<job>"; costs no Actions minutes)
#
# Job commands live in scripts/ci/jobs.sh (shared with ci.yml). Emulator jobs
# lease a port slot (scripts/ci/lease.sh), so several local_ci.sh runs, GitHub
# runners and agents can run at the same time on this Mac.
#
# Emulator port overrides (TA-39, e.g. parallel local runs):
#   LOCAL_CI_FIRESTORE_PORT=18080 LOCAL_CI_FIRESTORE_HUB_PORT=14400 \
#   LOCAL_CI_AUTH_PORT=19099 LOCAL_CI_STORAGE_PORT=19199 \
#   LOCAL_CI_FUNCTIONS_PORT=15001 LOCAL_CI_LOGGING_PORT=14500 \
#   LOCAL_CI_FIRESTORE_WEBSOCKET_PORT=19150 bash scripts/local_ci.sh <sha>
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

# shellcheck source=emulator_ports.env.sh
source "$SCRIPT_DIR/emulator_ports.env.sh"

JOBS_ARG=""
CHANGED_BASE=""
NO_APK=0
POST_STATUS=0
TARGET=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --jobs) JOBS_ARG="${2:-}"; shift 2 ;;
    --jobs=*) JOBS_ARG="${1#--jobs=}"; shift ;;
    --changed) CHANGED_BASE="origin/dev"; shift ;;
    --changed=*) CHANGED_BASE="${1#--changed=}"; shift ;;
    --no-apk) NO_APK=1; shift ;;
    --post-status) POST_STATUS=1; shift ;;
    -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
    -*) echo "local_ci: unknown option $1" >&2; exit 2 ;;
    *) TARGET="$1"; shift ;;
  esac
done
if [[ -z "$TARGET" ]]; then
  echo "Usage: bash scripts/local_ci.sh [--jobs a,b] [--changed[=base]] [--no-apk] [--post-status] <git-sha>" >&2
  exit 2
fi
set -- "$TARGET"

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

# Job selection (scripts/ci/jobs.sh is read from the SHA under test).
# shellcheck source=ci/jobs.sh
if [[ -f "$SRC/scripts/ci/jobs.sh" ]]; then
  source "$SRC/scripts/ci/jobs.sh"
else
  echo "local_ci: $SHA predates scripts/ci; this script needs a SHA that has it" >&2
  exit 2
fi
if [[ -n "$JOBS_ARG" ]]; then
  JOBS="${JOBS_ARG//,/ }"
elif [[ -n "$CHANGED_BASE" ]]; then
  git fetch origin --quiet || true
  JOBS="$(git diff --name-only "$(git merge-base "$CHANGED_BASE" "$SHA")" "$SHA" | ci_jobs_for_paths)"
else
  JOBS="$CI_JOBS_ALL"
fi
if [[ "$NO_APK" -eq 1 ]]; then
  JOBS="$(echo " $JOBS " | sed 's/ android-dev-build / /; s/^ *//; s/ *$//')"
fi
for j in $JOBS; do
  ci_job_exists "$j" || { echo "local_ci: unknown job '$j'" >&2; exit 2; }
done
echo "jobs: $JOBS" | tee -a "$OUT/full.log"
export CI_SHA="$SHA"

REPO_SLUG="$(git remote get-url origin | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')"
post_status() {
  [[ "$POST_STATUS" -eq 1 ]] || return 0
  local job="$1" result="$2" duration="$3" state
  case "$result" in PASS) state=success ;; PENDING) state=pending ;; *) state=failure ;; esac
  gh api "repos/${REPO_SLUG}/statuses/${SHA}" \
    -f state="$state" -f context="local-ci/${job}" \
    -f description="${result} in ${duration}s on $(hostname -s) (local_ci.sh)" >/dev/null 2>&1 \
    || echo "warning: could not post status for ${job}" >>"$OUT/full.log"
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
  post_status "$slug" PENDING 0
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
  post_status "$slug" "$result" "$duration"
  return 0
}

# --- jobs: commands and timeouts from scripts/ci/jobs.sh (same as ci.yml) ---
for j in $JOBS; do
  run_job "$j" "$(ci_job_timeout "$j")" "bash scripts/ci/run_job.sh $j"
done

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
  echo "Jobs come from \`scripts/ci/jobs.sh\` (same commands as \`.github/workflows/ci.yml\`). \`android-dev-build\` is local-only."
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
