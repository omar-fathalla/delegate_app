#!/usr/bin/env bash
# Fail if any Maestro YAML under maestro/ lacks appId before the document separator.
# Every file invoked via runFlow (including logout-via-menu) must declare its own config.
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

# mapfile is bash 4+; macOS /bin/bash is 3.2 on tashil-delegate-mac.
yaml_files=()
while IFS= read -r _f; do
  yaml_files+=("$_f")
done < <(find maestro -type f -name '*.yaml' | sort)


[[ "${#yaml_files[@]}" -gt 0 ]] || fail "no Maestro YAML files under maestro/"

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
