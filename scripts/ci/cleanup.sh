#!/usr/bin/env bash
# Remove CI leftovers on this Mac. Only touches CI-owned things:
#   /tmp/local-ci/<sha>       older than 14 days (+ git worktree prune)
#   /Users/Shared/tashil-ci/tmp/slot-*   files older than 2 days
#   stale leases              (dead owner pid or older than 4 h)
#   Tashil-CI-* simulators    booted but not leased -> shut down
# Never touches DerivedData, your own simulators/emulators, or runner _work.
#
#   bash scripts/ci/cleanup.sh [--dry-run]
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lease.sh
source "$HERE/lease.sh"
DRY=0
[[ "${1:-}" == "--dry-run" ]] && DRY=1
do_rm() { if (( DRY )); then echo "would remove $1"; else rm -rf "$1" && echo "removed $1"; fi; }

for d in /tmp/local-ci/*; do
  [[ -d "$d" ]] || continue
  if [[ -n "$(find "$d" -maxdepth 0 -mtime +14 2>/dev/null)" ]]; then do_rm "$d"; fi
done
(( DRY )) || git -C "$HERE/../.." worktree prune 2>/dev/null || true

if [[ -d /Users/Shared/tashil-ci/tmp ]]; then
  while IFS= read -r f; do do_rm "$f"; done \
    < <(find /Users/Shared/tashil-ci/tmp -mindepth 2 -maxdepth 2 -mtime +2 2>/dev/null)
fi

for pool_dir in "$CI_LEASE_ROOT"/*; do
  [[ -d "$pool_dir" ]] || continue
  for d in "$pool_dir"/*; do
    [[ -d "$d" ]] || continue
    if (( DRY )); then
      read -r pid _ started _ <"$d/owner" 2>/dev/null || true
      ps -p "${pid:-0}" >/dev/null 2>&1 || echo "would reap stale lease $d"
    elif _ci_lease_reap_if_stale "$d"; then
      echo "reaped stale lease $d"
    fi
  done
done

while read -r name udid; do
  n="${name#Tashil-CI-}"
  if [[ ! -d "$CI_LEASE_ROOT/ios-sim/$n" ]]; then
    if (( DRY )); then echo "would shut down $name"; else xcrun simctl shutdown "$udid" >/dev/null 2>&1 && echo "shut down $name"; fi
  fi
done < <(xcrun simctl list devices booted 2>/dev/null | sed -nE 's/^ +(Tashil-CI-[0-9]+) \(([0-9A-F-]{36})\).*/\1 \2/p')

echo "cleanup done$( (( DRY )) && echo ' (dry run)')"
