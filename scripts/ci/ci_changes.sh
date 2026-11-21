#!/usr/bin/env bash
# Which CI jobs this change needs, for .github/workflows/ci.yml (job "changes").
#   bash scripts/ci/ci_changes.sh <base-ref>   # PR: jobs for files changed vs base
#   bash scripts/ci/ci_changes.sh --all        # push to dev / manual run: every job
# Prints the job ids padded with spaces (" analyze test "), so ci.yml can test
# contains(needs.changes.outputs.jobs, ' test '). Same mapping as local_ci --changed.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=jobs.sh
source "$HERE/jobs.sh"
if [[ "${1:-}" == "--all" || -z "${1:-}" ]]; then
  jobs="$CI_JOBS_GITHUB"
else
  base="$1"
  files="$(git diff --name-only "$base"...HEAD)" || { echo "ci_changes: diff vs $base failed, running all" >&2; jobs="$CI_JOBS_GITHUB"; }
  if [[ -z "${jobs:-}" ]]; then
    jobs="$(printf '%s\n' "$files" | ci_jobs_for_paths)"
    echo "ci_changes: $(printf '%s\n' "$files" | grep -c . || true) changed file(s) vs $base" >&2
  fi
fi
echo " $jobs "
