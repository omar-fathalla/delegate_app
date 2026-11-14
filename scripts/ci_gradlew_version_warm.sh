#!/usr/bin/env bash
# Run ./gradlew --version from android/ (cwd set by workflow) with network-flake retries.
set -euo pipefail

_NETWORK_FLAKE_RE='(504|502|503|Gateway Time-out|gateway timeout|timed out|timeout|download failed|gradle-distributions|distributionUrl|Could not (GET|HEAD)|Connection reset|Broken pipe|UNAVAILABLE|Service Unavailable|HTTP response code)'

_MAX_ATTEMPTS=4
_BACKOFF_SECS=(15 45 90)

attempt=1
while [[ "$attempt" -le "$_MAX_ATTEMPTS" ]]; do
  set +e
  out="$(./gradlew --version 2>&1)"
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
  echo "ci_gradlew_version_warm: wrapper download flake (attempt ${attempt}/${_MAX_ATTEMPTS}); retrying in ${sleep_secs}s..." >&2
  sleep "$sleep_secs"
  attempt=$((attempt + 1))
done
