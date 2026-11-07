#!/bin/sh
# Runs immediately after Flutter's xcode_backend.sh "build" so dev Crashlytics is
# unlinked from FlutterGeneratedPluginSwiftPackage before Xcode resolves SPM.
set -eu

. "${SRCROOT:?}/scripts/tashil_dev_build_context.sh"

if tashil_is_dev_build; then
  /bin/sh "${SRCROOT}/scripts/strip_dev_crashlytics_spm_package.sh"
fi
