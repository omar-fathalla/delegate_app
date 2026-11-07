# Patrol iOS dev sim — frozen artifact manifest (PR #218)

Manifests record **SHA-256** hashes of binaries produced for **`tashil-dev`** Patrol smoke on a **clean git worktree** at a fixed commit. They are regenerated on Mac after `build-for-testing` / `patrol test` — not on Linux CI.

## Files

| Pattern | Purpose |
| --- | --- |
| `frozen-<shortsha>.yaml` | Human-readable manifest keyed by `git_commit` |
| `frozen-<shortsha>.json` | Same content for tooling |

Until Mac capture, placeholders use `capture_status: pending_mac` and `sha256: null`.

## Regenerate (Mac)

```bash
git fetch origin chore/patrol-dev-smoke
git worktree add /tmp/patrol-freeze-<shortsha> <full-sha>
cd /tmp/patrol-freeze-<shortsha>
git status   # must be clean

# After dev sim build-for-testing (see patrol_test/README.md):
patrol test -t patrol_test/smoke_dev_login_test.dart --flavor dev \
  --dart-define=ENV=dev \
  --dart-define=PATROL_DEV_SECRET='<from Project store>' \
  -d <SIM_UDID>

./scripts/patrol_ios_dev_freeze_manifest.sh <shortsha>
git add patrol_test/manifest/frozen-<shortsha>.{yaml,json}
```

## Verify hashes

```bash
shasum -a 256 path/to/Runner.app/Runner
shasum -a 256 path/to/RunnerUITests.xctest
shasum -a 256 path/to/*.xctestrun
```

Compare output to `artifacts.*.sha256` in the manifest for the same `git_commit`.
