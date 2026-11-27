#!/usr/bin/env bash
# TAS-394: fail when a Patrol target file has no result line in the run log.
# Usage: patrol_check_ran_targets.sh <patrol-output-log> <target.dart>...
set -euo pipefail

log="${1:?usage: patrol_check_ran_targets.sh <log> <target>...}"
shift
[[ -f "$log" ]] || { echo "patrol-ran-targets: ERROR: log not found: $log" >&2; exit 1; }

missing=()
# Strip colours once into a file. (Piping sed into `grep -q` under pipefail
# fails whenever grep stops early and sed gets SIGPIPE.)
plain="$(mktemp -t patrol-ran-plain.XXXXXX)"
trap 'rm -f "$plain"' EXIT
sed -E 's/\x1b\[[0-9;]*[A-Za-z]//g' "$log" >"$plain"

# Patrol prints no result line for a test skipped by `skip:` (e.g. an
# Android-only file on iOS). A file whose tests are all platform-skipped marks
# itself with `// patrol-ran-targets: may-skip-on <platform>`; it may be absent
# only on that platform and only while the summary reports enough skips.
platform="${PATROL_RAN_TARGETS_PLATFORM:-}"
skipped="$(grep -Eo 'Skipped: [0-9]+' "$plain" | tail -n 1 | grep -Eo '[0-9]+' || true)"
skipped="${skipped:-0}"
allowed=0
for t in "$@"; do
  base="$(basename "$t")"
  # Result lines look like: "✅ dev: name (/integration_x_test.dart) (66s)".
  if grep -qF "(/$base)" "$plain"; then
    continue
  fi
  if [[ -n "$platform" && -f "$t" ]] \
    && grep -qE "^// patrol-ran-targets: may-skip-on .*\b$platform\b" "$t" \
    && (( allowed < skipped )); then
    allowed=$((allowed + 1))
    echo "patrol-ran-targets: $base skipped on $platform (allowed)"
    continue
  fi
  missing+=("$base")
done

if [[ "${#missing[@]}" -gt 0 ]]; then
  echo "patrol-ran-targets: ERROR: ${#missing[@]} of $# target file(s) never ran:" >&2
  printf '  - %s\n' "${missing[@]}" >&2
  exit 1
fi
echo "patrol-ran-targets: OK ($# target file(s) reported results)"
