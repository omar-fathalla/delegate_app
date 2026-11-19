#!/usr/bin/env bash
# Register extra delegate_app runners on this Mac (Phase 2 of docs/ci/local-ci-plan.md)
# and run each as a LaunchDaemon. Jobs on them share port slots via scripts/ci/lease.sh.
#
# Usage (as fathalla, needs `gh` with repo admin + the Mac admin password):
#   bash scripts/ci/add_delegate_runners.sh 2 3
#
# Each runner N: /Users/delegate-ci/actions-runner-N, name tashil-delegate-mac-N,
# labels self-hosted,macOS,ARM64,delegate-app,slot-N.
# The registration token is fetched per runner, passed via env, never printed.
set -euo pipefail

REPO="omar-fathalla/delegate_app"
RUNNER_USER="delegate-ci"
BASE="/Users/${RUNNER_USER}/actions-runner"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[[ $# -ge 1 ]] || { echo "usage: add_delegate_runners.sh <n> [n...]   e.g. 2 3" >&2; exit 2; }
[[ -x "$BASE/config.sh" ]] || { echo "missing $BASE (first runner install)" >&2; exit 1; }

for n in "$@"; do
  [[ "$n" =~ ^[2-9]$ ]] || { echo "runner number must be 2-9, got $n" >&2; exit 2; }
  name="tashil-delegate-mac-$n"
  dir="${BASE}-$n"
  if [[ -f "$dir/.runner" ]]; then
    echo "$name already configured in $dir, only (re)installing the daemon"
  else
    echo "== $name: copying runner binaries to $dir"
    sudo -u "$RUNNER_USER" mkdir -p "$dir"
    # .runner_migrated alone makes config.sh say "already configured".
    sudo -u "$RUNNER_USER" rsync -a --exclude '_work' --exclude '_diag' \
      --exclude '.runner*' --exclude '.credentials*' --exclude '.service' \
      --exclude '.env' --exclude '.path' "$BASE/" "$dir/"
    sudo -u "$RUNNER_USER" rm -f "$dir/.runner_migrated"
    token="$(gh api -X POST "repos/${REPO}/actions/runners/registration-token" -q .token)"
    echo "== $name: registering with GitHub"
    sudo -u "$RUNNER_USER" env RUNNER_TOKEN="$token" bash -c '
      cd "$0" && ./config.sh --unattended --replace \
        --url "https://github.com/$1" --token "$RUNNER_TOKEN" \
        --name "$2" --labels "delegate-app,slot-$3" --work _work >/dev/null
    ' "$dir" "$REPO" "$name" "$n"
    unset token
  fi
  RUNNER_NAME="$name" RUNNER_DIR="$dir" sudo -E bash "$HERE/install_delegate_runner_daemon.sh"
done

gh api "repos/${REPO}/actions/runners" -q '.runners[] | "\(.name)\t\(.status)\t\([.labels[].name]|join(","))"'
