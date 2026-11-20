#!/usr/bin/env bash
# TAS-107: list (default) or kill Firebase emulator processes left behind by a
# crashed or cancelled run. Only this user's processes whose parent is gone
# (ppid 1) and that are older than --min-age minutes; a running test's
# emulator always has a live parent, so it is never touched.
#
# Usage:
#   bash scripts/kill_stale_emulators.sh                 # list
#   bash scripts/kill_stale_emulators.sh --kill          # kill them
#   bash scripts/kill_stale_emulators.sh --min-age 10    # minutes (default 30)
set -euo pipefail

KILL=0
MIN_AGE=30
while [[ $# -gt 0 ]]; do
  case "$1" in
    --kill) KILL=1 ;;
    --min-age) MIN_AGE="$2"; shift ;;
    -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

# ps etime: [[dd-]hh:]mm:ss -> minutes
etime_minutes() {
  local t="$1" d=0 h=0 m=0
  if [[ "$t" == *-* ]]; then d="${t%%-*}"; t="${t#*-}"; fi
  local IFS=:
  # shellcheck disable=SC2206
  local parts=($t)
  case "${#parts[@]}" in
    3) h="${parts[0]}"; m="${parts[1]}" ;;
    2) m="${parts[0]}" ;;
  esac
  echo $(( 10#$d * 1440 + 10#$h * 60 + 10#$m ))
}

found=0
while read -r pid ppid etime cmd; do
  [[ "$ppid" == 1 ]] || continue
  [[ "$cmd" == *cloud-firestore-emulator* || "$cmd" == *"emulators:"* || "$cmd" == *cloud-storage-rules-runtime* ]] || continue
  age="$(etime_minutes "$etime")"
  [[ "$age" -ge "$MIN_AGE" ]] || continue
  found=1
  ports="$(lsof -nP -a -p "$pid" -iTCP -sTCP:LISTEN 2>/dev/null | awk 'NR>1{sub(/.*:/,"",$9); print $9}' | sort -u | tr '\n' ' ')"
  cwd="$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -1)"
  echo "orphaned emulator pid $pid, up ${age} min, ports: ${ports:-none}"
  echo "  cwd: ${cwd:-?}"
  echo "  cmd: ${cmd:0:140}"
  if [[ "$KILL" -eq 1 ]]; then
    kill "$pid" && echo "  killed"
  fi
done < <(ps -U "$(id -u)" -o pid=,ppid=,etime=,command=)

if [[ "$found" -eq 0 ]]; then
  echo "no orphaned emulators older than ${MIN_AGE} min"
elif [[ "$KILL" -eq 0 ]]; then
  echo "run again with --kill to stop them"
fi
