# Local CI on the Mac — plan

Status: **phases 0–4 implemented** (2026-11-19); remaining human steps are marked **Human**. Owner: delegate-app team.
Goal: CI that runs entirely on our Mac (no GitHub-hosted minutes), stays the merge gate, and lets several runners and several AI agents work at the same time without stepping on each other.

---

## 1. Where we are today

| Fact | Evidence |
| --- | --- |
| `CI` and `PR User Test builds` workflows are **disabled manually** since 2026-11-11. No PR has had CI since 2026-11-10. | `gh workflow list --all` |
| Runner `tashil-delegate-mac` (user `delegate-ci`, `/Users/delegate-ci/actions-runner`) is **offline**. | `gh api repos/.../actions/runners` |
| Every `ci.yml` job already targets that self-hosted runner. | `runs-on: [self-hosted, macOS, ARM64, delegate-app]` |
| Workflows still on **GitHub-hosted** runners: `deploy-ios.yml` (`macos-latest`), `android-release.yml`, `firestore-indexes.yml`, `actions-cleanup.yml` (`ubuntu-latest`). | `grep runs-on .github/workflows` |
| `ci.yml` / `pr-user-test-builds.yml` call `~/mac-resources/ci_delegate_app_lock_*.sh`, which **do not exist** on the runner user. `build-web` would fail on first run. | `ls /Users/delegate-ci/mac-resources` |
| Firebase emulator ports are fixed defaults (8080, 9099, 9199, 4400, ...). Two jobs running emulators at once collide. Override env exists (`scripts/emulator_ports.env.sh`, TA-39). | |
| One Flutter SDK (3.44.5) shared by everything. Its startup lock is held only while the tool checks its cache, so parallel `flutter` commands in **different checkouts** are fine; one SDK is enough. | |
| Mac: 14 cores, 24 GB RAM, ~375 GB free. | `sysctl`, `df` |

### Why the minutes ran out (billing, November 2026)

| SKU | Repo | Usage | Net |
| --- | --- | --- | --- |
| Actions Linux | **Tashil-Data-Sharing** | 5,686 min | $30.54 |
| Actions Linux | delegate_app | 2,937 min | $9.20 |
| Actions macOS 3-core | delegate_app | 166 min | $10.26 |
| Actions storage | delegate_app | 352 GB-h | $0.00 |

No self-hosted line appears: **self-hosted jobs are free**. Disabling `ci.yml` (already self-hosted) saved nothing. The cost is GitHub-hosted runners: mostly the Data-Sharing repo, then delegate_app's `ubuntu-latest` workflows and `deploy-ios.yml` on `macos-latest`.

### Why the runner went offline

`tashil-delegate-mac` was installed as a **LaunchAgent** of `delegate-ci` (`~/Library/LaunchAgents/...plist`). A LaunchAgent only runs while that user has a login session; the runner log stops on 2026-11-13. The Data-Sharing runners are **LaunchDaemons** (`/Library/LaunchDaemons`, `UserName=tashil-ci`) and stayed up. Fix: `scripts/ci/install_delegate_runner_daemon.sh`.

---

## 2. Target design

```
                 GitHub (control plane only: PRs, statuses, branch protection)
                         ▲  free: self-hosted jobs + commit-status API
        ┌────────────────┼──────────────────────────────┐
        │ Mac (delegate-ci user)                        │
        │                                               │
        │  runner-1 ─┐                                  │
        │  runner-2 ─┼─► scripts/ci/run_job.sh <job>    │◄── agents / humans run the
        │  runner-3 ─┘        │                         │    SAME script locally
        │                     ▼                         │    (scripts/local_ci.sh)    
        │        slot lease (1..N) ──► ports, SDK, tmp  │
        │        device lease      ──► sim / emulator   │
        │        results ──► build/ci-results/<sha>/    │
        └───────────────────────────────────────────────┘
```

Three rules make it safe for many runners and agents at once:

1. **One source of truth for commands.** Each CI job is a function in `scripts/ci/jobs.sh`, run by `scripts/ci/run_job.sh`. `ci.yml` steps become `bash scripts/ci/run_job.sh analyze`. Agents run the exact same thing locally. No more drift between docs, skill and workflow.
2. **Everything shared is leased.** A job never touches a port, SDK copy, simulator or emulator it has not leased. Leases live in `/Users/Shared/tashil-ci/leases/` (`mkdir`-atomic lock dirs with PID + timestamp; stale after PID death or timeout).
3. **Results are written down, not remembered.** Every run writes `result.json` + logs under `build/ci-results/<sha>/<job>/`. Local runs can publish the result as a **GitHub commit status** (`gh api repos/:owner/:repo/statuses/<sha>`) — this costs zero minutes and shows up on the PR like a normal check.

### 2.1 Slots (CPU-bound isolation)

`N = 3` slots to start (14 cores / 24 GB: two heavy builds + one light job).

| Per slot `k` | Value |
| --- | --- |
| Firebase emulator ports | default + `k*10000` (slot 1: Firestore 18080, Auth 19099, Storage 19199, Hub 14400, Logging 14500, WS 19150, Functions 15001) via the existing `LOCAL_CI_*` env. Slots never use the default ports, so a developer running `npm run test:rules` by hand never collides with CI. |
| Flutter SDK | shared (see §1) |
| `PUB_CACHE`, Gradle home | shared (both are safe for concurrent readers; Gradle has its own locking) |
| TMPDIR | `/Users/Shared/tashil-ci/tmp/slot-k` |

### 2.2 Devices (exclusive)

| Pool | Members | Max concurrent |
| --- | --- | --- |
| iOS simulators | clones `Tashil-CI-1`, `Tashil-CI-2` (from pinned iPhone 17 runtime) | 2 |
| Android emulators | `Pixel_6a` instances on ports 5560, 5562 (`-read-only` so they can run twice) | 2 |
| Physical devices | never used by CI | 0 |

Device leases are separate from slots; a Maestro/Patrol job holds one slot + one device. Device is booted on lease, shut down on release (matches the "boot when needed, shut down when finished" preference).

### 2.3 Job matrix

| Job | Trigger | Slot | Device | ≈ time |
| --- | --- | --- | --- | --- |
| `analyze` | every PR push | ✓ | – | 2 min |
| `test` | every PR push | ✓ | – | 8 min |
| `guards` (6 static scripts) | every PR push | ✓ (light) | – | 1 min |
| `rules` (all `test:rules:*` + e2e) | PR touches rules/functions, and nightly | ✓ | – | 6 min |
| `functions` | PR touches `functions/**`, and nightly | ✓ | – | 3 min |
| `build-web` | PR touches `lib/**`/`web/**` | ✓ | – | 5 min |
| `mac-gate` (APK dev + Maestro + Patrol) | push to `dev` (merged SHA), and on demand | ✓ | ✓ | 25 min |

Path filters cut most PRs to `analyze + test + guards` (~10 min).

---

## 3. Multi-agent protocol

For Claude / Cursor / other agents working in parallel:

1. **One agent = one git worktree** under `worktrees/<branch>`. Never two agents in one checkout.
2. Before pushing, the agent runs `bash scripts/local_ci.sh --changed --no-apk <sha>` (picks jobs by changed paths, leases a slot, waits in queue if all slots are busy).
3. The agent reads `build/ci-results/<sha>/summary.json`, not raw logs, to decide pass/fail.
4. Device tests only through `local_ci.sh mac-gate` (never by booting a simulator by hand) so leases are respected.
5. Agents never: re-enable/disable workflows, change runner services, merge, or touch prod. Those stay human actions.
6. The `pr-gate` skill calls `local_ci.sh` for stages 1–4 and 7 instead of listing commands itself.

---

## 4. Rollout phases

Each phase ends with a check that proves it works. Do not start the next phase until the check passes.

### Phase 0 — Unblock (today, ~1 h, mostly human)
- [x] Billing confirms the burn is GitHub-hosted runners (§1).
- [ ] Merge PR #382 (removes `~/mac-resources` locks, uses a GitHub `concurrency` group instead) — **human**.
      Caveat: a GitHub concurrency group keeps **one running + one pending**; a third queued job in the same group is cancelled. Fine with one runner; Phase 2 replaces it with leases.
- [ ] `sudo bash scripts/ci/install_delegate_runner_daemon.sh` (LaunchAgent → LaunchDaemon) — **human, needs admin password**.
- [ ] Re-enable `CI` workflow (`gh workflow enable CI`).
- **Check:** runner shows `online` and PR #383 gets a full green CI run.
- Follow-up (not Phase 0): move Data-Sharing's `ubuntu-latest` workflows to its own Mac runners — that is where most minutes go.

### Phase 1 — One command source (~½ day)
- [x] `scripts/ci/jobs.sh` (job bodies, timeouts, path→job selection) + `scripts/ci/run_job.sh <job>`.
      Reconciled the drift between `ci.yml` and the old `local_ci.sh`: guards now include xctestrun + holds_authority checks; rules runs **every** `test:rules*` script in `package.json` (auto-discovered) + all 4 rules e2e suites.
- [x] `ci.yml` steps call `run_job.sh`; `test/scripts/ci_tooling_test.sh` (in ios-guards) fails if anyone inlines a job command again.
- [x] `scripts/local_ci.sh` uses the same jobs; new `--jobs`, `--changed[=base]`, `--no-apk`, `--post-status` (commit status `local-ci/<job>`, zero Actions minutes).
- **Check:** `local_ci.sh` and the GitHub run give the same pass/fail on the same SHA.

### Phase 2 — Parallel slots (~½ day)
- [x] Lease library (`scripts/ci/lease.sh`): `mkdir`-atomic, owner pid/user/time, stale = dead pid or > 4 h, release only by owner. Root `/Users/Shared/tashil-ci/leases` (1777, shared by all CI users).
- [x] Slot env (ports, TMPDIR) applied by `run_job.sh` for emulator jobs. `CI_SLOTS` (default 3).
      Verified 2026-11-19: `rules` + `p0-scripts` + `emulator-ports` in parallel took slots 2/3/1 (ports 28080/38080/18080), no port errors, all leases released.
- [ ] Register runners 2 and 3: `bash scripts/ci/add_delegate_runners.sh 2 3` — **human, needs admin password**.
- **Check:** two PRs pushed at once both run `rules` simultaneously without port errors.

### Phase 3 — Device pool + mac-gate (done 2026-11-19, pending secrets)
- [x] iOS simulator pool `scripts/ci/devices.sh`: leases `Tashil-CI-<n>` (pool `ios-sim`, `CI_IOS_SIMS` default 2), created on first use with the newest iOS runtime, booted on lease, shut down on release. Verified: create → boot → lease → shutdown → release.
- [x] `mac-gate` job in `scripts/ci/jobs.sh`: iOS dev build + install on the leased sim → `mac_gate_preflight.sh` → APK dev → Maestro journeys → Patrol (`-d <sim>`). Narrow with `CI_MAC_GATE_STEPS="ios-install preflight"`.
- [x] `local_ci.sh` seeds the gitignored `ios/config/dev/GoogleService-Info.plist` (and `android/local.properties`) into its clean checkout.
- [ ] **Human:** create `~/.tashil-ci.env` (mode 600) with `PATROL_DEV_SECRET=` and `TASHIL_MAESTRO_DEV_SECRET=` from the Project store (`internal/tashil-dev-test-accounts.txt`). Without it, `mac-gate` stops at the secrets check.
- Android emulators: not pooled. Maestro and Patrol run on iOS today; the APK is only built. Add an `android-emu` pool when an Android device test exists.
- Runs as the console user (fathalla), not the `delegate-ci` runner: that account owns the simulators, Android SDK, Maestro, Patrol and keys, and a LaunchDaemon has no GUI session for simulators.
- **Check:** a merge to `dev` produces a `local-ci/mac-gate` commit status without anyone touching the Mac (needs Phase 4 agent + secrets).

### Phase 4 — Gate + hygiene (done 2026-11-19)
- Branch protection is **not available**: private repo on GitHub Free returns 403 ("Upgrade to GitHub Pro"). Instead:
  - [x] `scripts/ci/merge_guard.sh <pr> [--merge]`: refuses unless every CI job is green on the PR head, from GitHub checks **or** `local-ci/<job>` statuses. Agents and the `pr-gate` skill merge only through it.
- [x] `scripts/ci/mac_agent.sh`, installed with `bash scripts/ci/install_mac_agent.sh` (LaunchAgent, every 10 min, no sudo):
  - runner health: notification when a `delegate-app` runner is offline > 15 min, and when it is back;
  - after each merge: new `origin/dev` SHA → `local_ci.sh --jobs mac-gate --post-status`;
  - nightly (first pass after 00:30 Cairo): full `local_ci.sh --no-apk --post-status` on `dev`, then cleanup.
  - Why local, not a GitHub `schedule`: scheduled workflows run from the default branch (`main`), and they would need the runner user to own simulators and secrets.
- [x] `scripts/ci/cleanup.sh [--dry-run]`: only CI-owned leftovers (old `/tmp/local-ci`, slot tmp, stale leases, unleased `Tashil-CI-*` sims). Never DerivedData or personal devices.
- Hosted workflows left as they are, on purpose:
  - `android-release.yml`, `deploy-ios.yml`: team rule in `ci.yml` header ("Do not change release workflows").
  - `firestore-indexes.yml`: documented to stay on `ubuntu-latest` (prod read-only secret, must not hold the Mac); path-filtered, ~1 min per run.
  - `actions-cleanup.yml`: weekly, ~1 min.
  - The real minute burn is **Tashil-Data-Sharing** (§1); moving its workflows to its own Mac runners is a separate task in that repo.
- **Check:** one week with no manual CI babysitting and `delegate_app` hosted minutes ≈ release builds only.

---

## 5. Risks

| Risk | Mitigation |
| --- | --- |
| Mac is a single point of failure (sleep, reboot, updates) | `caffeinate`/energy settings for the runner user, launchd services auto-start, health check alert |
| RAM pressure with 2 devices + 2 builds | device pool max 2, heavy jobs max 2; tune after Phase 2 metrics |
| Stale leases after crash | PID check + timeout in `lease.sh`, cleanup cron |
| Secrets leaking into logs | `::add-mask::`, never `set -x` in jobs that read secrets |
| Self-hosted runner running untrusted PR code | repo is private; keep "require approval for fork PRs" on |
