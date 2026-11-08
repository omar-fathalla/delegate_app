#!/usr/bin/env bash
# Build a Flutter APK with one automatic retry on Gradle/network flakes (504, timeouts).
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "ci_gradle_flutter_apk: usage: $0 -- <flutter build apk args...>" >&2
  echo "  Example: $0 -- --release --flavor prod --dart-define=ENV=prod" >&2
  exit 1
fi

if [[ "$1" == "--" ]]; then
  shift
else
  echo "ci_gradle_flutter_apk: ERROR: pass flutter build args after --" >&2
  exit 1
fi

_NETWORK_FLAKE_RE='(504|Gateway Time-out|gateway timeout|timed out|timeout|download failed|Could not (GET|HEAD)|Connection reset|Broken pipe|UNAVAILABLE|Service Unavailable)'

attempt=1
while [[ "$attempt" -le 2 ]]; do
  set +e
  out="$(flutter build apk "$@" 2>&1)"
  code=$?
  set -e
  if [[ "$code" -eq 0 ]]; then
    echo "$out"
    exit 0
  fi
  echo "$out" >&2
  if [[ "$attempt" -eq 2 ]] || ! echo "$out" | grep -Eqi "$_NETWORK_FLAKE_RE"; then
    exit "$code"
  fi
  echo "ci_gradle_flutter_apk: network/Gradle flake detected; retrying once..." >&2
  sleep 15
  attempt=$((attempt + 1))
done
