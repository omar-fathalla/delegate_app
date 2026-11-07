# Patrol iOS dev sim — frozen artifact manifest (PR #218)

Manifests record **SHA-256** hashes of binaries produced for **`tashil-dev`** Patrol smoke on a **clean git worktree** at a fixed commit. They are regenerated on Mac after `build-for-testing` / `patrol test` — not on Linux CI.

## Source of truth: latest `build/ios_integ` `.xctestrun`

Patrol runs through **`build/ios_integ`**. The freeze script **does not** fingerprint `build/ios/iphonesimulator/Runner.app` when it disagrees with the integration graph.

1. Pick the **newest** `*.xctestrun` under `build/ios_integ` (by mtime).
2. Parse `UITargetAppPath`, `TestHostPath`, and `TestBundlePath` via `patrol_test/manifest/xctestrun_resolve.py` (placeholder expansion: `__TESTROOT__`, `__TESTHOST__`).
3. Tree-hash the **resolved** paths:

| Manifest key | xctestrun field | Typical product |
| --- | --- | --- |
| `artifacts.runner_app` | `UITargetAppPath` | `.../Debug-dev-iphonesimulator/Runner.app` |
| `artifacts.test_runner` | `TestHostPath` | `.../RunnerUITests-Runner.app` |
| `artifacts.runner_ui_tests` | `TestBundlePath` | `.../PlugIns/RunnerUITests.xctest` |

When those directories exist on disk, **`test_runner.path` and tree hashes must not be `null`**.

The manifest also records the `.xctestrun` file path, format version, blueprint name, raw key values, and the file hash.

## Files

| Pattern | Purpose |
| --- | --- |
| `frozen-<shortsha>.yaml` | Human-readable manifest keyed by `git_commit` |
| `frozen-<shortsha>.json` | Same content for tooling |
| `xctestrun_resolve.py` | Shared plist resolver (freeze script + tests) |
| `test_xctestrun_resolve.sh` | Resolver unit check (no Mac build required) |

Until Mac capture, placeholders use `capture_status: pending_mac` and `sha256: null`.

## Regenerate (Mac)

```bash
git fetch origin chore/patrol-dev-smoke
git worktree add /tmp/patrol-freeze-<shortsha> <full-sha>
cd /tmp/patrol-freeze-<shortsha>
git status   # must be clean

# After dev sim build-for-testing (see patrol_test/README.md).
# Reuse existing build/ios_integ when smoke already ran in this worktree.
./scripts/patrol_ios_dev_freeze_manifest.sh <shortsha>
git add patrol_test/manifest/frozen-<shortsha>.{yaml,json}
```

`patrol_ios_dev_freeze_manifest.sh` fingerprints **`.app` / `.xctest` directories** with a sorted per-file manifest (deterministic across machines). Key binaries (`Runner`, `RunnerUITests`, `Info.plist`, `*.xctestrun`) are listed separately; compare a Mac rebuild to the committed `frozen-<shortsha>.*` files for the same `git_commit`.

## Verify resolver (Linux / Mac)

```bash
chmod +x patrol_test/manifest/test_xctestrun_resolve.sh
./patrol_test/manifest/test_xctestrun_resolve.sh
```
