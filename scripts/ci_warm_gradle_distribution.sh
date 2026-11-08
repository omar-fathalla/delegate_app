#!/usr/bin/env bash
# Materialize gitignored wrapper, then warm distribution (repo-root entry for local/CI parity).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
bash "${ROOT}/scripts/ci_materialize_gradle_wrapper.sh"
(cd "${ROOT}/android" && bash "${ROOT}/scripts/ci_gradlew_version_warm.sh")
