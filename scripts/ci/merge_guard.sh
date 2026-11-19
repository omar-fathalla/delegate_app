#!/usr/bin/env bash
# Merge gate for dev. GitHub branch protection needs GitHub Pro on a private
# repo, so this script is the gate instead: humans and agents merge through it.
#
#   bash scripts/ci/merge_guard.sh <pr>           # check only
#   bash scripts/ci/merge_guard.sh <pr> --merge   # check, then gh pr merge --merge
#
# A job counts as green when, on the PR head SHA, EITHER the GitHub check run
# (ci.yml job name) succeeded OR the local commit status local-ci/<job> is
# success (scripts/local_ci.sh --post-status). Any other state blocks.
set -euo pipefail
GH_REPO="omar-fathalla/delegate_app"
PR="${1:?usage: merge_guard.sh <pr> [--merge]}"
MERGE=0; [[ "${2:-}" == "--merge" ]] && MERGE=1

# job id | GitHub check-run name (ci.yml)
REQUIRED="
analyze|Analyze
test|Test
ios-guards|iOS dev config (static)
android-guards|Android dev config (static)
p0-scripts|P0 scripts (emulators)
functions|Functions lint & test
rules|Firestore rules & delegate login e2e (emulators)
build-web|Build web (release)
"

read -r sha base state draft < <(gh pr view "$PR" -R "$GH_REPO" --json headRefOid,baseRefName,state,isDraft \
  -q '"\(.headRefOid) \(.baseRefName) \(.state) \(.isDraft)"')
[[ "$state" == OPEN ]] || { echo "PR #$PR is $state" >&2; exit 1; }
[[ "$draft" == false ]] || { echo "PR #$PR is a draft" >&2; exit 1; }
echo "PR #$PR -> $base @ ${sha:0:8}"

checks="$(gh api "repos/${GH_REPO}/commits/${sha}/check-runs?per_page=100" \
  -q '.check_runs[] | "\(.name)|\(.status)|\(.conclusion)"')"
statuses="$(gh api "repos/${GH_REPO}/commits/${sha}/status" -q '.statuses[] | "\(.context)|\(.state)"')"

blocked=0
while IFS='|' read -r job name; do
  [[ -n "$job" ]] || continue
  gh_line="$(grep -F "${name}|" <<<"$checks" | head -1 || true)"
  local_line="$(grep -F "local-ci/${job}|" <<<"$statuses" | head -1 || true)"
  if [[ "$gh_line" == *"|completed|success" ]]; then
    printf '  %-16s PASS (GitHub)\n' "$job"
  elif [[ "$local_line" == *"|success" ]]; then
    printf '  %-16s PASS (local-ci)\n' "$job"
  else
    printf '  %-16s BLOCK  github=%s local=%s\n' "$job" "${gh_line#*|}" "${local_line#*|}"
    blocked=1
  fi
done <<<"$REQUIRED"

if (( blocked )); then
  echo "merge_guard: NOT mergeable (fix or rerun the blocked jobs)" >&2
  exit 1
fi
echo "merge_guard: all required jobs green"
if (( MERGE )); then
  gh pr merge "$PR" -R "$GH_REPO" --merge
fi
