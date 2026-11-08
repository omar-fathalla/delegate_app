#!/usr/bin/env bash
# Build a Flutter APK with retries on Gradle wrapper/distribution network flakes (504, timeouts).
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

# Match transient download/CDN issues only — not compile or dependency resolution failures.
_NETWORK_FLAKE_RE='(504|502|503|Gateway Time-out|gateway timeout|timed out|timeout|download failed|gradle-distributions|distributionUrl|Could not (GET|HEAD)|Connection reset|Broken pipe|UNAVAILABLE|Service Unavailable|SSLHandshakeException|Remote host terminated)'

_MAX_ATTEMPTS=4
_BACKOFF_SECS=(15 45 90)

attempt=1
while [[ "$attempt" -le "$_MAX_ATTEMPTS" ]]; do
  set +e
  out="$(flutter build apk "$@" 2>&1)"
  code=$?
  set -e
  if [[ "$code" -eq 0 ]]; then
    echo "$out"
    exit 0
  fi
  echo "$out" >&2
  if [[ "$attempt" -eq "$_MAX_ATTEMPTS" ]] || ! echo "$out" | grep -Eqi "$_NETWORK_FLAKE_RE"; then
    exit "$code"
  fi
  sleep_idx=$((attempt - 1))
  sleep_secs="${_BACKOFF_SECS[$sleep_idx]:-${_BACKOFF_SECS[-1]}}"
  echo "ci_gradle_flutter_apk: network/Gradle flake detected (attempt ${attempt}/${_MAX_ATTEMPTS}); retrying in ${sleep_secs}s..." >&2
  sleep "$sleep_secs"
  attempt=$((attempt + 1))
done
