#!/usr/bin/env bash
# TAS-394: fail when a Patrol target file has no result line in the run log.
# Usage: patrol_check_ran_targets.sh <patrol-output-log> <target.dart>...
set -euo pipefail

log="${1:?usage: patrol_check_ran_targets.sh <log> <target>...}"
shift
[[ -f "$log" ]] || { echo "patrol-ran-targets: ERROR: log not found: $log" >&2; exit 1; }

missing=()
for t in "$@"; do
  base="$(basename "$t")"
  # Result lines look like: "✅ dev: name (/integration_x_test.dart) (66s)".
  if ! sed -E 's/\x1b\[[0-9;]*[A-Za-z]//g' "$log" | grep -qF "(/$base)"; then
    missing+=("$base")
  fi
done

if [[ "${#missing[@]}" -gt 0 ]]; then
  echo "patrol-ran-targets: ERROR: ${#missing[@]} of $# target file(s) never ran:" >&2
  printf '  - %s\n' "${missing[@]}" >&2
  exit 1
fi
echo "patrol-ran-targets: OK ($# target file(s) reported results)"
