#!/usr/bin/env bash
# Cheap unit checks for xctestrun path resolution (Linux + Mac).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RESOLVER="$ROOT/patrol_test/manifest/xctestrun_resolve.py"
FIXTURE="$ROOT/patrol_test/manifest/fixtures/sample-ui-format1.xctestrun"

if [[ ! -f "$RESOLVER" ]]; then
  echo "missing resolver: $RESOLVER" >&2
  exit 1
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

mkdir -p "$tmpdir/Runner.app" "$tmpdir/RunnerUITests-Runner.app/PlugIns/RunnerUITests.xctest"
touch "$tmpdir/Runner.app/Runner"
touch "$tmpdir/RunnerUITests-Runner.app/PlugIns/RunnerUITests.xctest/RunnerUITests"
cp "$FIXTURE" "$tmpdir/sample.xctestrun"

# Plain variables instead of `declare -A`: macOS ships bash 3.2 (no associative arrays).
got_ui_target_app="" got_test_runner_app="" got_test_bundle="" got_blueprint_name=""
while IFS='=' read -r key value; do
  case "$key" in
    ui_target_app) got_ui_target_app="$value" ;;
    test_runner_app) got_test_runner_app="$value" ;;
    test_bundle) got_test_bundle="$value" ;;
    blueprint_name) got_blueprint_name="$value" ;;
  esac
done < <(python3 "$RESOLVER" "$tmpdir/sample.xctestrun")

expected_ui="$tmpdir/Runner.app"
expected_host="$tmpdir/RunnerUITests-Runner.app"
expected_bundle="$tmpdir/RunnerUITests-Runner.app/PlugIns/RunnerUITests.xctest"

assert_eq() {
  local label="$1" want="$2" have="$3"
  if [[ "$want" != "$have" ]]; then
    echo "FAIL $label: want=$want have=$have" >&2
    exit 1
  fi
}

assert_eq ui_target_app "$expected_ui" "$got_ui_target_app"
assert_eq test_runner_app "$expected_host" "$got_test_runner_app"
assert_eq test_bundle "$expected_bundle" "$got_test_bundle"
assert_eq blueprint_name "RunnerUITests" "$got_blueprint_name"

echo "OK patrol_test/manifest/test_xctestrun_resolve.sh"
