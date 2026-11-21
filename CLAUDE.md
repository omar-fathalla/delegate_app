@AGENTS.md

# Working on a change (every task, every agent)

Lifecycle: **start-work → work → pr-gate → merge_guard**. Rules in Arabic: `docs/DEV_WORKFLOW_RULES_AR.md` (هـ).

1. **Start**: use the `start-work` skill. New branch + worktree from `origin/dev`, never commit on `dev` / `main`.
2. **Work**: every behaviour change ships with its test in the same branch. dev / `tashil-dev` and fake accounts only.
3. **Check**: `bash scripts/local_ci.sh --changed --no-apk HEAD` whenever useful. The `pre-push` hook runs a fast check (analyze + changed tests); CI runs only the jobs the change needs.
4. **Finish**: use the `pr-gate` skill on the PR, then merge only through `bash scripts/ci/merge_guard.sh <pr> --merge`, and only after the user says yes.

Never push, merge, deploy, or comment on a PR without the user's explicit yes in chat. Never print secrets.
