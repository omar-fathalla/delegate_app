#!/bin/sh
# Exit 0 when the current shell environment is a Tashil dev iOS build; 1 otherwise.
# Used from Podfile and tests (no secrets).
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
# shellcheck source=tashil_dev_build_context.sh
. "${SCRIPT_DIR}/tashil_dev_build_context.sh"
if tashil_is_dev_build; then
  exit 0
fi
exit 1
