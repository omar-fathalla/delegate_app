---
name: pr-gate
description: Run the Tashil delegate-app release gate for one PR, from scope check through local checks, CI, merge and the Mac six-tool gate, ending with an evidence report. Use when a PR or branch is "done", before or after merging into dev, or when the user says "شغّل البوابة", "pr gate", "خلصت البي آر", "اعمل تست للبي آر", "six-tool gate", "Mac gate".
---

# PR gate — Tashil delegate app

One pass per PR, in order. Each stage has a **done when** line. Stop at the first red stage, report it, and do not move on until it is green or the user explicitly waives it (record the waiver in the report).

Sources of truth — read them instead of trusting this file if they disagree:
- `docs/testing/tool-roles.md` (the six tools)
- `docs/testing/mac-gate-preflight.md`
- `.github/workflows/ci.yml` (exact CI commands)

Fast path for stages 1–4: `bash scripts/local_ci.sh --changed --no-apk <sha>` runs exactly the CI jobs (from `scripts/ci/jobs.sh`) needed for the changed files, leases a port slot so it can run beside other agents and runners, and writes `/tmp/local-ci/<sha>/SUMMARY.md`. Add `--post-status` (only with the user's yes) to show results on the PR. The stage details below say what each job covers and how to judge it.

Hard rules:
- `dev` / `tashil-dev` only, fake accounts only. Never point any step at prod (`practice-firebase-72df1` is read-only territory).
- Secrets come from env (`PATROL_DEV_SECRET`, `TASHIL_MAESTRO_DEV_SECRET`). Never print, commit or paste them.
- Never merge, push, or post a PR comment without the user's yes in chat.
- Talk to the user in Egyptian Arabic; keep commands and file names as-is.

---

## Stage 0 — Scope

1. Identify PR number, head branch, base (`dev`), head SHA: `gh pr view <N> --json number,headRefName,baseRefName,headRefOid,isDraft,files`.
   No PR yet → use the current branch and `git diff --name-only origin/dev...HEAD`.
2. Classify changed files into buckets; they decide which conditional stages run:

| Bucket | Paths | Triggers |
| --- | --- | --- |
| dart | `lib/**`, `test/**` | 1, 2 |
| ui | `lib/**/presentation/**`, `lib/core/widgets/**`, `lib/l10n/**`, `lib/config/theme/**` | 2b goldens |
| rules | `firestore.rules`, `storage.rules`, `firestore.indexes.json`, `firestore/**` | 4 |
| functions | `functions/**` | 4 |
| native | `ios/**`, `android/**`, `macos/**` | 3, 7 |
| e2e | `maestro/**`, `patrol_test/**` | 3, 7 |
| scripts | `scripts/**`, `.github/**` | 3 |

3. Write a short scope summary (PR, SHA, buckets, stages that will run) before running anything.

**Done when:** scope summary is written.

## Stage 1 — Static analysis

```bash
flutter pub get --enforce-lockfile
flutter analyze --no-fatal-warnings --no-fatal-infos
```

CI tolerates warnings, this gate does not tolerate **new** ones: run `flutter analyze` on the changed `.dart` files only and require zero warnings/errors there.

**Done when:** no errors anywhere, no warnings in changed files.

## Stage 2 — Dart tests

a. Targeted first (fast feedback): `flutter test <test files mirroring changed lib files>`.
   A changed `lib/features/x/...` file with no matching test under `test/features/x/...` → flag it as a coverage gap in the report (not a blocker unless it is domain/bloc logic for attendance, geofence, time, money or permissions).
b. Goldens, only if bucket `ui`: run the golden tests (`grep -rl matchesGoldenFile test`). If a golden diff is intentional, regenerate with `--update-goldens` **only after the user confirms** the new look.
c. Full suite with coverage:
   ```bash
   flutter test --concurrency=1 --coverage
   awk -F: '/^LF:/{t+=$2} /^LH:/{h+=$2} END{printf "line coverage: %.1f%% (%d/%d)\n", h*100/t, h, t}' coverage/lcov.info
   ```
   Report the coverage number; compare with the last report if one exists. A drop is a warning, not a blocker.

**Done when:** all tests pass.

## Stage 3 — Static guards

Always run (they are cheap):

```bash
bash scripts/ios_dev_config_check.sh
bash scripts/android_dev_config_check.sh
bash scripts/maestro_check_flow_headers.sh
bash scripts/patrol_check_integration_targets.sh
bash ios/scripts/test_offline_sync_bgtask_registration.sh
bash patrol_test/manifest/test_xctestrun_resolve.sh
```

All guards must stay bash 3.2 compatible (macOS stock bash): no `declare -A`, `mapfile`, `${var,,}`.

**Done when:** every script exits 0.

## Stage 4 — Backend (only if bucket `rules` or `functions`)

Install deps the way CI does first (`npm install --no-audit --no-fund` at the root — there is no root lockfile — and `npm --prefix functions ci`); without them every suite fails with `Cannot find module '@firebase/rules-unit-testing'`, which is not a rules failure. Then copy the exact commands from the `rules` and `functions` jobs in `.github/workflows/ci.yml` (they run on emulators, never on a real project). Also run any `test:rules:*` script in `package.json` that ci.yml does not list yet, and flag the gap.

**Done when:** all emulator suites pass.

## Stage 5 — Push and CI

1. Ask the user before pushing. Policy: batch commits, draft PR while iterating, one push when ready.
2. After the push: `gh pr checks <N> --watch` (run in background). Do not poll in a loop.

**Done when:** every required check is green. A red check → read its log (`gh run view <id> --log-failed`), fix or report, back to the failing stage.

## Stage 6 — Merge (user action)

Ask the user to merge (or to approve you merging). Merge only through `bash scripts/ci/merge_guard.sh <pr> --merge` (dev has no branch protection on GitHub Free; this script is the gate). Record the **merged `dev` SHA** — stage 7 runs on that SHA, not the PR head.

**Done when:** merged SHA is known and checked out locally (`git fetch origin dev && git checkout --detach <sha>`).

## Stage 7 — Mac six-tool gate (on merged dev SHA)

Run on the Mac worker. Simulator is booted only for this stage and shut down at the end.

```bash
TASHIL_PREFLIGHT_KEEP_BOOT=1 bash scripts/mac_gate_preflight.sh
flutter build apk --flavor dev --dart-define=ENV=dev
bash maestro/run-dev-user-journeys.sh
bash scripts/patrol_run_dev_integration.sh
xcrun simctl shutdown "${TASHIL_SIM_UDID:-8CD21E86-592A-4ED5-9F41-BF90CB9796C6}"
```

- Open the preflight screenshot and confirm it shows **مندوب / موظف إداري**, not the home screen.
- Missing secrets env → stop and ask the user to export them; never ask them to paste the value in chat.
- A Patrol/Maestro failure: rerun that one target once. Passes on rerun → mark **flaky** in the report (still green). Fails twice → red.

**Done when:** preflight, APK, Maestro and Patrol are all green, simulator shut down.

## Stage 8 — Evidence report and close-out

Write `build/gate-reports/<YYYY-MM-DD>-pr<N>-<short-sha>.md` (`build/` is git-ignored):

```markdown
# Gate — PR #<N> — <short-sha> (merged dev)
Date / machine / Flutter version
| Stage | Result | Notes |
| 0 Scope | buckets: ... | |
| 1 Analyze | ✅/❌ | new warnings: 0 |
| 2 Tests | ✅ | N passed, coverage X% (prev Y%) |
| 3 Guards | ✅ | |
| 4 Backend | ✅ / skipped (no rules/functions) | |
| 5 CI | ✅ | run URL |
| 7 Mac gate | ✅ | screenshot path, flaky: ... |
Waivers: ...
Follow-ups: missing tests, flaky targets, CI gaps
```

Then:
1. Offer to post the report as a PR comment (only on the user's yes).
2. List follow-ups (missing tests, flaky targets, rules suites not in CI). Each real one becomes its own task, not part of this PR.
3. Clean up: simulator shut down, no stray `coverage/` or golden failure files staged.

**Done when:** report saved, user has the summary, follow-ups listed.
