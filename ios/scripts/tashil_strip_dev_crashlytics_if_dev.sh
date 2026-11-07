#!/bin/sh
# Run Crashlytics SPM strip when the environment is dev (shared entry for Podfile / CI).
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
export SRCROOT="${SRCROOT:-${SCRIPT_DIR}/..}"
if ! "${SCRIPT_DIR}/tashil_is_dev_build.sh"; then
  exit 0
fi
exec /bin/sh "${SCRIPT_DIR}/strip_dev_crashlytics_spm_package.sh"
