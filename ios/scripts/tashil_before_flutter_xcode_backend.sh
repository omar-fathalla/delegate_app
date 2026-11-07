#!/bin/sh
# Dev-only: strip Crashlytics from Flutter SPM integration *before* xcode_backend.sh
# regenerates/resolves packages so Xcode does not link FIRCrashlytics on dev builds.
set -eu

. "${SRCROOT:?}/scripts/tashil_dev_build_context.sh"

if tashil_is_dev_build; then
  /bin/sh "${SRCROOT}/scripts/strip_dev_crashlytics_spm_package.sh"
fi
