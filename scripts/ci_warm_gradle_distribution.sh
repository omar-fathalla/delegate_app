#!/usr/bin/env bash
# Materialize gitignored Gradle wrapper files and download the distribution before flutter build apk.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ANDROID="${ROOT}/android"
SRC="${FLUTTER_ROOT:?FLUTTER_ROOT must be set}/bin/cache/artifacts/gradle_wrapper"

if [[ ! -f "${SRC}/gradlew" ]]; then
  echo "ci_warm_gradle_distribution: missing Flutter gradle_wrapper artifact at ${SRC}" >&2
  echo "ci_warm_gradle_distribution: run 'flutter precache' if this persists" >&2
  exit 1
fi

cp "${SRC}/gradlew" "${ANDROID}/gradlew"
chmod +x "${ANDROID}/gradlew"
mkdir -p "${ANDROID}/gradle/wrapper"
cp "${SRC}/gradle/wrapper/gradle-wrapper.jar" "${ANDROID}/gradle/wrapper/gradle-wrapper.jar"

_NETWORK_FLAKE_RE='(504|502|503|Gateway Time-out|gateway timeout|timed out|timeout|download failed|gradle-distributions|distributionUrl|Could not (GET|HEAD)|Connection reset|Broken pipe|UNAVAILABLE|Service Unavailable|HTTP response code)'

_MAX_ATTEMPTS=4
_BACKOFF_SECS=(15 45 90)

attempt=1
while [[ "$attempt" -le "$_MAX_ATTEMPTS" ]]; do
  set +e
  out="$(cd "${ANDROID}" && ./gradlew --version 2>&1)"
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
  echo "ci_warm_gradle_distribution: wrapper download flake (attempt ${attempt}/${_MAX_ATTEMPTS}); retrying in ${sleep_secs}s..." >&2
  sleep "$sleep_secs"
  attempt=$((attempt + 1))
done
