#!/bin/sh
# Tashil: Crashlytics / upload-symbols guard for dev builds (plan r2 §2.4).
#
# Inventory at the time this was added (dev 17e6486): no Runner build phase
# calls upload-symbols or any Crashlytics/FlutterFire script. This guard keeps
# it that way for *-dev: if a phase or scheme action that uploads symbols is
# ever added, dev builds fail instead of reaching any Firebase project. It also
# re-checks that the plist inside the built .app is tashil-dev.
# On prod configurations it does nothing (exit 0): prod behaviour is unchanged.
set -eu

fail() {
  echo "error: [Tashil dev-upload-guard] $*" >&2
  exit 1
}

PB=/usr/libexec/PlistBuddy
PY="${SRCROOT:-}/scripts/tashil_plist_tools.py"

pl_pid() {
  f="$1"
  if [ -x "$PB" ]; then
    $PB -c 'Print :PROJECT_ID' "$f" 2>/dev/null || true
  else
    python3 "$PY" get "$f" PROJECT_ID 2>/dev/null || true
  fi
}

APP_ENV="${APP_ENV:-}"
case "$APP_ENV" in
  prod)
    echo "[Tashil dev-upload-guard] prod configuration: no-op."
    exit 0
    ;;
  dev) ;;
  *) fail "APP_ENV='$APP_ENV'; expected dev or prod." ;;
esac

PATTERN='upload-symbols|upload_symbols|FirebaseCrashlytics/run|firebase_crashlytics.*upload|flutterfire upload-crashlytics-symbols|crashlytics:symbols:upload'

PROJ="${PROJECT_FILE_PATH:-${SRCROOT:-}/Runner.xcodeproj}"
[ -f "$PROJ/project.pbxproj" ] || fail "project.pbxproj not found under $PROJ."
if grep -Eq "$PATTERN" "$PROJ/project.pbxproj"; then
  fail "a build phase in $PROJ/project.pbxproj references symbol upload; not allowed for dev (plan §2.4)."
fi
for scheme in "$PROJ"/xcshareddata/xcschemes/*.xcscheme; do
  [ -f "$scheme" ] || continue
  if grep -Eq "$PATTERN" "$scheme"; then
    fail "scheme $(basename "$scheme") has a pre/post action that uploads symbols; not allowed for dev."
  fi
done

if [ -n "${TARGET_BUILD_DIR:-}" ] && [ -n "${UNLOCALIZED_RESOURCES_FOLDER_PATH:-}" ]; then
  APP_RES="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
  f="$APP_RES/GoogleService-Info.plist"
  [ -f "$f" ] || fail "no GoogleService-Info.plist in the built app."
  pid=$(pl_pid "$f")
  [ "$pid" = "tashil-dev" ] || fail "bundled PROJECT_ID='$pid', expected tashil-dev."
  # No production Firebase config file may sit anywhere in the dev .app.
  if grep -rl --include='*.plist' 'practice-firebase-72df1' "$APP_RES" >/dev/null 2>&1; then
    fail "a plist in the dev app mentions practice-firebase-72df1."
  fi
fi
echo "[Tashil dev-upload-guard] OK: no symbol upload phase, bundled project tashil-dev."
