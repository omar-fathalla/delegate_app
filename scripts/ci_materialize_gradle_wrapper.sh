#!/usr/bin/env bash
# Copy gitignored Gradle wrapper scripts/jar from Flutter tooling cache into android/.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ANDROID="${ROOT}/android"
SRC="${FLUTTER_ROOT:?FLUTTER_ROOT must be set}/bin/cache/artifacts/gradle_wrapper"

if [[ ! -f "${SRC}/gradlew" ]]; then
  echo "ci_materialize_gradle_wrapper: missing Flutter gradle_wrapper artifact at ${SRC}" >&2
  exit 1
fi

cp "${SRC}/gradlew" "${ANDROID}/gradlew"
chmod +x "${ANDROID}/gradlew"
mkdir -p "${ANDROID}/gradle/wrapper"
cp "${SRC}/gradle/wrapper/gradle-wrapper.jar" "${ANDROID}/gradle/wrapper/gradle-wrapper.jar"
