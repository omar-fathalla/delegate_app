#!/usr/bin/env bash
# TAS-200: warm the Firebase Hosting CDN right after a web deploy.
#
#   bash scripts/warm_web_cdn.sh <base-url> [build-dir] [rounds]
#   bash scripts/warm_web_cdn.sh https://tashil-dev.web.app
#   bash scripts/warm_web_cdn.sh https://hr.sw-point.com build/web 3
#
# Right after a deploy every CDN edge is empty, and the first visitor waits
# while the edge pulls main.dart.js (about 2 MB brotli) from the slow origin:
# 25-48 s measured on 2026-11-21, against about 1 s once cached. This script
# requests the big files a few times so that wait is paid here, not by a user.
# It only warms the edge closest to the machine that runs it.
#
# Files: index.html, flutter_bootstrap.js, main.dart.js, and every file in
# <build-dir> (default build/web) of 100 KB or more. Without a build dir only
# the first three are requested. Exits 1 if any file is not 200 in the last
# round. bash 3.2 compatible.
set -euo pipefail

BASE="${1:-}"
BUILD_DIR="${2:-build/web}"
ROUNDS="${3:-3}"
MIN_BYTES="${WARM_MIN_BYTES:-102400}"

if [[ -z "$BASE" ]]; then
  sed -n 2,17p "$0" >&2
  exit 2
fi
BASE="${BASE%/}"

paths="index.html
flutter_bootstrap.js
main.dart.js"
if [[ -d "$BUILD_DIR" ]]; then
  big="$(cd "$BUILD_DIR" && find . -type f -size +"$((MIN_BYTES / 1024))"k | sed 's|^\./||' | LC_ALL=C sort)"
  if [[ -n "$big" ]]; then
    paths="$(printf '%s\n%s\n' "$paths" "$big" | awk 'NF && !seen[$0]++')"
  fi
else
  echo "warm_web_cdn: no $BUILD_DIR, warming the default files only" >&2
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

failed=0
round=1
while [[ $round -le $ROUNDS ]]; do
  echo "== round $round/$ROUNDS"
  failed=0
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    out="$(curl -s -o /dev/null -D "$tmp/h" -H 'Accept-Encoding: br, gzip' \
      --max-time 120 -w '%{http_code} %{time_total}' "$BASE/$p" || echo "000 0")"
    code="${out%% *}"
    secs="${out#* }"
    cache="$(grep -i '^x-cache:' "$tmp/h" 2>/dev/null | tr -d '\r' | awk '{print $2}' || true)"
    printf '%s %6ss %-5s %s\n' "$code" "$secs" "${cache:--}" "$p"
    [[ "$code" == "200" ]] || failed=1
  done <<EOF
$paths
EOF
  round=$((round + 1))
done

if [[ $failed -ne 0 ]]; then
  echo "warm_web_cdn: some files did not return 200 in the last round" >&2
  exit 1
fi
echo "warm_web_cdn: OK ($BASE)"
