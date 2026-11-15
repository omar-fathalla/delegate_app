#!/usr/bin/env bash
# TA-39: local_ci honors LOCAL_CI_FIRESTORE_PORT / LOCAL_CI_FIRESTORE_HUB_PORT.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if grep -q 'LOCAL_CI_FIRESTORE_PORT' "$ROOT/scripts/local_ci.sh" \
  && grep -q 'LOCAL_CI_FIRESTORE_HUB_PORT' "$ROOT/scripts/local_ci.sh"; then
  echo "ok: local_ci.sh references configurable emulator ports"
  exit 0
fi
echo "missing port env in local_ci.sh" >&2
exit 1