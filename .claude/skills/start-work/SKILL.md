---
name: start-work
description: Start any change in the Tashil delegate app the right way, on its own branch and worktree from the latest dev, with the testing rules set up from the first commit. Use whenever a new task, fix, feature or PR begins, or the user says "هبدأ شغل", "branch جديد", "افتح برانش", "عاوز اعدل", "start work", "new branch".
---

# Start work — Tashil delegate app

The lifecycle of every change is: **start-work → work (rules below) → pr-gate → merge_guard**.
This skill is the first step. `pr-gate` (`.claude/skills/pr-gate/SKILL.md`) is the last.
Full rules in Arabic: `docs/DEV_WORKFLOW_RULES_AR.md` section (هـ).

Talk to the user in Egyptian Arabic; keep commands and file names as-is.

## 1. Name the branch

`<type>/<short-kebab-name>` from `origin/dev`. Types:
`feat` (new behaviour) · `fix` (bug) · `test` (tests only) · `chore` (tooling, CI, deps) · `docs`.
One topic per branch. If the user's request has two unrelated topics, propose two branches.

## 2. Create the worktree

```bash
cd /Users/fathalla/Tashil-Employee/tashil-app
git fetch origin dev --quiet
git worktree add -b <type>/<name> ../worktrees/<name> origin/dev
cd ../worktrees/<name>
```

Then copy the gitignored local files the dev build needs (never commit them, never print them):

```bash
MAIN=/Users/fathalla/Tashil-Employee/worktrees/dev-latest   # any worktree that has them
cp "$MAIN/android/local.properties" android/ 2>/dev/null || true
mkdir -p ios/config/dev && cp "$MAIN/ios/config/dev/GoogleService-Info.plist" ios/config/dev/ 2>/dev/null || true
```

Make sure the hooks are on (once per clone, harmless to repeat):

```bash
bash scripts/ci/install_git_hooks.sh
```

## 3. Baseline

`flutter pub get --enforce-lockfile`, then `flutter analyze`. If dev itself is red, say so before changing anything, so the user knows the failure is not from this branch.

## 4. While working (rules)

- Commit on the branch only. The `pre-commit` hook refuses `dev` / `main`.
- Every behaviour change comes with a test in the same branch:
  Dart logic → `test/` unit or widget test · Firestore rules → `test/rules/*.test.js` ·
  Cloud Functions → `functions/test/` · a user flow → Maestro flow or Patrol test.
- `dev` / `tashil-dev` and fake accounts only. Logins for every role: the 34 seeded accounts
  (`functions/scripts/README-hr-web-fake-accounts.md`; passwords only in
  `functions/scripts/.hr-web-fake-accounts.local.json`, never print them).
- Do not change `pubspec.lock`, release workflows (`android-release`, `deploy-ios`), or prod.
- Quick check any time: `bash scripts/local_ci.sh --changed --no-apk HEAD` (only the jobs the changed files need).

## 5. Push and PR

- Push only when the user says so. The `pre-push` hook runs the same changed-files local CI and blocks a red push; it also refuses pushes to `dev` / `main`.
- Open the PR to `dev` as a draft; mark it ready when the work is done.

## 6. Finish

Run the `pr-gate` skill on the PR. Merge only with the user's yes, and only through:

```bash
bash scripts/ci/merge_guard.sh <pr> --merge
```

After the merge, remove the worktree (`git worktree remove ../worktrees/<name>`) once the user agrees.
