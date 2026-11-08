#!/usr/bin/env bash
# Patrol integration guard (Linux CI + Mac preflight):
#  - at least one patrol_test/integration_*.dart
#  - patrolTest titles must not contain XCTest-unsafe characters (e.g. /)
#  - when --targets is passed, ensure at least one matching integration file resolves
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() {
  echo "patrol-check-integration: ERROR: $*" >&2
  exit 1
}

shopt -s nullglob
integration_files=(patrol_test/integration_*.dart)
shopt -u nullglob

[[ "${#integration_files[@]}" -gt 0 ]] || fail "no patrol_test/integration_*.dart files (Patrol would run 0 integration tests)"

# patrolTest('title' ...) — disallow / and other characters that break native selectors.
while IFS= read -r hit; do
  [[ -z "$hit" ]] && continue
  fail "disallowed character in Patrol test title: $hit"
done < <(
  python3 - <<'PY' "${integration_files[@]}"
import re, sys
pat = re.compile(r"patrolTest\s*\(\s*['\"]([^'\"]+)['\"]")
bad = re.compile(r"[/\\]")
for path in sys.argv[1:]:
    text = open(path, encoding="utf-8").read()
    for m in pat.finditer(text):
        title = m.group(1)
        if bad.search(title):
            print(f"{path}: title={title!r}")
PY
)

targets_mode=0
targets=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --targets)
      shift
      targets_mode=1
      while [[ $# -gt 0 && "$1" != --* ]]; do
        targets+=("$1")
        shift
      done
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

if [[ "$targets_mode" -eq 1 ]]; then
  matched=0
  for pattern in "${targets[@]}"; do
    shopt -s nullglob
    for f in $pattern; do
      if [[ -f "$f" ]] && [[ "$f" =~ ^patrol_test/integration_.*\.dart$ ]]; then
        matched=$((matched + 1))
      fi
    done
    shopt -u nullglob
  done
  [[ "$matched" -gt 0 ]] || fail "Patrol --targets resolved to 0 integration tests: ${targets[*]}"
  echo "patrol-check-integration: OK ($matched target file(s), ${#integration_files[@]} integration suite file(s))"
else
  echo "patrol-check-integration: OK (${#integration_files[@]} integration file(s))"
fi
