#!/bin/sh
# Dev-only: remove any Crashlytics dylibs/bundles Xcode may have embedded despite SPM strip.
set -eu

. "${SRCROOT:?}/scripts/tashil_dev_build_context.sh"
if ! tashil_is_dev_build; then
  exit 0
fi

APP_DIR="${TARGET_BUILD_DIR:?}/${WRAPPER_NAME:-Runner.app}"
if [ ! -d "$APP_DIR" ]; then
  echo "[Tashil] OK (dev): no built .app at $APP_DIR; skip Crashlytics bundle strip."
  exit 0
fi

removed=0
framework="${APP_DIR}/Frameworks/FirebaseCrashlytics.framework"
if [ -e "$framework" ]; then
  rm -rf "$framework"
  removed=1
  echo "[Tashil] OK (dev): removed FirebaseCrashlytics.framework from app bundle."
fi

while IFS= read -r artifact; do
  rm -rf "$artifact"
  removed=1
  echo "[Tashil] OK (dev): removed $(basename "$artifact") from app bundle."
done <<EOF
$(find "$APP_DIR" -maxdepth 4 \( -iname '*Crashlytics*.framework' -o -iname 'Firebase_FirebaseCrashlytics.bundle' \) 2>/dev/null)
EOF

if [ "$removed" -eq 0 ]; then
  echo "[Tashil] OK (dev): no Crashlytics frameworks/bundles in app bundle."
fi

if find "$APP_DIR" -maxdepth 4 \( -path '*/Frameworks/FirebaseCrashlytics.framework' -o -iname 'Firebase_FirebaseCrashlytics.bundle' \) 2>/dev/null | grep -q .; then
  echo "error: [Tashil] Crashlytics binary still present in dev app bundle after strip." >&2
  exit 1
fi
