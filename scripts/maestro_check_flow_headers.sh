#!/usr/bin/env bash
# Fail if any Maestro flow/subflow YAML lacks appId before the document separator.
# Subflows referenced via runFlow must carry their own appId (Maestro does not inherit).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() {
  echo "maestro-check-headers: ERROR: $*" >&2
  exit 1
}

check_yaml() {
  local path="$1"
  local header
  header="$(awk '
    /^[[:space:]]*#/ { next }
    /^---$/ { exit }
    { print }
  ' "$path")"

  if ! grep -q '^appId:[[:space:]]*[^[:space:]]' <<<"$header"; then
    fail "$path: missing appId: header before ---"
  fi
}

shopt -s nullglob
yaml_files=(maestro/flows/*.yaml maestro/subflows/*.yaml)
shopt -u nullglob

[[ "${#yaml_files[@]}" -gt 0 ]] || fail "no Maestro YAML files under maestro/flows or maestro/subflows"

for f in "${yaml_files[@]}"; do
  check_yaml "$f"
done

# Optional: if Maestro CLI is installed, run syntax check as a second line of defense.
if command -v maestro >/dev/null 2>&1; then
  for f in "${yaml_files[@]}"; do
    maestro check-syntax "$f" || fail "maestro check-syntax failed for $f"
  done
fi

echo "maestro-check-headers: OK (${#yaml_files[@]} files)"
