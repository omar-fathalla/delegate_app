#!/usr/bin/env bash
# Turn on the repo's git hooks (.githooks/) for this clone and all its worktrees.
#   bash scripts/ci/install_git_hooks.sh           # on
#   bash scripts/ci/install_git_hooks.sh --remove  # off
# The setting lives in the shared .git/config; a worktree whose branch has no
# .githooks/ folder simply runs no hooks.
set -euo pipefail
if [[ "${1:-}" == "--remove" ]]; then
  git config --unset core.hooksPath || true
  echo "git hooks off"
  exit 0
fi
git config core.hooksPath .githooks
echo "git hooks on: core.hooksPath=.githooks (pre-commit: no commits on dev/main; pre-push: local CI on changed files)"
