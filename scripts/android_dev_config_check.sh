#!/usr/bin/env bash
# Static Android dev/prod flavor + Firebase wiring checks (Linux/macOS, no SDK required).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() {
  echo "android-dev-config-check: ERROR: $*" >&2
  exit 1
}

echo "== Repo root: $ROOT"

DEV_GS="$ROOT/android/app/src/dev/google-services.json"
[[ -f "$DEV_GS" ]] || fail "missing $DEV_GS"

PROD_GS="$ROOT/android/app/google-services.json"
[[ -f "$PROD_GS" ]] || fail "missing $PROD_GS"

GRADLE="$ROOT/android/app/build.gradle.kts"
[[ -f "$GRADLE" ]] || fail "missing $GRADLE"

grep -q 'flavorDimensions += "env"' "$GRADLE" || fail "build.gradle.kts missing env flavor dimension"
grep -q 'create("dev")' "$GRADLE" || fail "build.gradle.kts missing dev product flavor"
grep -q 'applicationIdSuffix = ".dev"' "$GRADLE" || fail "dev flavor must set applicationIdSuffix .dev"
grep -q 'com.google.gms.google-services' "$GRADLE" || fail "google-services plugin not applied"

python3 <<'PY'
import json
from pathlib import Path

dev_gs = Path("android/app/src/dev/google-services.json")
data = json.loads(dev_gs.read_text(encoding="utf-8"))
pid = data.get("project_info", {}).get("project_id")
if pid != "tashil-dev":
    raise SystemExit(f"dev google-services project_id must be tashil-dev (got {pid!r})")

clients = data.get("client") or []
pkgs = [
    c.get("client_info", {}).get("android_client_info", {}).get("package_name")
    for c in clients
]
if "com.tashil.delegate.dev" not in pkgs:
    raise SystemExit(f"dev google-services must include com.tashil.delegate.dev (got {pkgs})")

prod_gs = Path("android/app/google-services.json")
pdata = json.loads(prod_gs.read_text(encoding="utf-8"))
ppid = pdata.get("project_info", {}).get("project_id")
if ppid != "practice-firebase-72df1":
    raise SystemExit(f"prod google-services project_id must be practice-firebase-72df1 (got {ppid!r})")

# Prod default client should remain the store package (not .dev).
prod_pkgs = [
    c.get("client_info", {}).get("android_client_info", {}).get("package_name")
    for c in (pdata.get("client") or [])
]
if "com.tashil.delegate" not in prod_pkgs:
    raise SystemExit(f"prod google-services missing com.tashil.delegate (got {prod_pkgs})")
PY

[[ -f "$ROOT/scripts/android_dev_distribute.sh" ]] || fail "missing scripts/android_dev_distribute.sh"
[[ -f "$ROOT/android/README_DEV_FLAVOR.md" ]] || fail "missing android/README_DEV_FLAVOR.md"

echo "android-dev-config-check: OK"