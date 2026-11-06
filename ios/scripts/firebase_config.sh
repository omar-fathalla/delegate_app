#!/bin/sh
# Tashil: per-flavor Firebase config for iOS (plan PLAN_IOS_DEV_FIREBASE_AR_r2 §1.3, §2.2).
#
#   firebase_config.sh check    Early build phase. Fails before compiling when the
#                               Xcode configuration (APP_ENV) and --dart-define=ENV
#                               disagree, or when ios/config/<env>/GoogleService-Info.plist
#                               is missing or points at the wrong project/bundle.
#   firebase_config.sh install  Late build phase. Copies that plist into the .app,
#                               writes TashilEnv and (dev only) the data-collection
#                               flags into the built Info.plist, then re-verifies.
#
# Fail closed: any doubt exits 1. There is no fallback to the production plist,
# and a dev build never reads ios/config/prod.
set -eu

PROD_PROJECT_ID="practice-firebase-72df1"
DEV_PROJECT_ID="tashil-dev"
PB=/usr/libexec/PlistBuddy
SCRIPT_DIR="$(CDPATH= cd "$(dirname "$0")" && pwd)"
PY="$SCRIPT_DIR/tashil_plist_tools.py"

fail() {
  echo "error: [Tashil firebase-config] $*" >&2
  exit 1
}

# PlistBuddy exists on macOS; GitHub Actions (Ubuntu) uses Python plistlib.
pl_get() {
  _f="$1"
  _k="$2"
  if [ -x "$PB" ]; then
    $PB -c "Print :$_k" "$_f" 2>/dev/null || true
  else
    python3 "$PY" get "$_f" "$_k" 2>/dev/null || true
  fi
}

mode="${1:-}"
APP_ENV="${APP_ENV:-}"
CONFIGURATION="${CONFIGURATION:-?}"

case "$APP_ENV" in
  dev) EXPECTED_PROJECT_ID="$DEV_PROJECT_ID" ;;
  prod) EXPECTED_PROJECT_ID="$PROD_PROJECT_ID" ;;
  *) fail "APP_ENV='$APP_ENV' for configuration '$CONFIGURATION'; expected dev or prod (see ios/Flutter/Env-*.xcconfig)." ;;
esac

[ -n "${PRODUCT_BUNDLE_IDENTIFIER:-}" ] || fail "PRODUCT_BUNDLE_IDENTIFIER is empty."
[ -n "${SRCROOT:-}" ] || fail "SRCROOT is empty."

# --dart-define=ENV=... reaches Xcode base64-encoded in DART_DEFINES.
dart_env=""
if [ -n "${DART_DEFINES:-}" ]; then
  for enc in $(printf '%s' "$DART_DEFINES" | tr ',' ' '); do
    dec=$(printf '%s' "$enc" | base64 --decode 2>/dev/null || true)
    case "$dec" in
      ENV=*) dart_env="${dec#ENV=}" ;;
    esac
  done
fi

check_env_match() {
  if [ "$APP_ENV" = dev ]; then
    [ "$dart_env" = dev ] || fail "Configuration '$CONFIGURATION' is dev but ENV='$dart_env'. Build with --flavor dev --dart-define=ENV=dev."
  else
    case "$dart_env" in
      "" | prod) ;;
      *) fail "Configuration '$CONFIGURATION' is prod but ENV='$dart_env'. Use --flavor prod (ENV=prod or no ENV)." ;;
    esac
  fi
}

# verify_plist <file> <label>
verify_plist() {
  f="$1"
  [ -f "$f" ] || fail "$2: $f is missing."
  pid=$(pl_get "$f" PROJECT_ID)
  bid=$(pl_get "$f" BUNDLE_ID)
  [ "$pid" = "$EXPECTED_PROJECT_ID" ] || fail "$2: PROJECT_ID='$pid', expected '$EXPECTED_PROJECT_ID' for APP_ENV=$APP_ENV."
  [ "$bid" = "$PRODUCT_BUNDLE_IDENTIFIER" ] || fail "$2: BUNDLE_ID='$bid', expected '$PRODUCT_BUNDLE_IDENTIFIER'."
  if [ "$APP_ENV" = dev ] && grep -q "$PROD_PROJECT_ID" "$f"; then
    fail "$2: dev plist mentions $PROD_PROJECT_ID."
  fi
}

SRC="$SRCROOT/config/$APP_ENV/GoogleService-Info.plist"

case "$mode" in
  check)
    check_env_match
    verify_plist "$SRC" "source"
    echo "[Tashil firebase-config] check OK: APP_ENV=$APP_ENV ENV='${dart_env}' project=$EXPECTED_PROJECT_ID bundle=$PRODUCT_BUNDLE_IDENTIFIER"
    ;;
  install)
    check_env_match
    verify_plist "$SRC" "source"
    [ -n "${TARGET_BUILD_DIR:-}" ] && [ -n "${UNLOCALIZED_RESOURCES_FOLDER_PATH:-}" ] && [ -n "${INFOPLIST_PATH:-}" ] \
      || fail "TARGET_BUILD_DIR / UNLOCALIZED_RESOURCES_FOLDER_PATH / INFOPLIST_PATH not set."
    APP_RES="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
    APP_INFO="$TARGET_BUILD_DIR/$INFOPLIST_PATH"
    [ -f "$APP_INFO" ] || fail "built Info.plist not found at $APP_INFO."
    DEST="$APP_RES/GoogleService-Info.plist"
    rm -f "$DEST"
    cp "$SRC" "$DEST"
    verify_plist "$DEST" "bundle"

    # TashilEnv is read by AppDelegate to decide whether native configure() runs.
    if [ -x "$PB" ]; then
      $PB -c "Delete :TashilEnv" "$APP_INFO" >/dev/null 2>&1 || true
      $PB -c "Add :TashilEnv string $APP_ENV" "$APP_INFO"
      if [ "$APP_ENV" = dev ]; then
        # Plan §2.2: no data collection in dev. FirebaseAppDelegateProxyEnabled stays default.
        for kv in \
          "FirebaseAutomaticDataCollectionEnabled bool false" \
          "FirebaseCrashlyticsCollectionEnabled bool false" \
          "FIREBASE_ANALYTICS_COLLECTION_ENABLED bool false" \
          "FIREBASE_ANALYTICS_COLLECTION_DEACTIVATED bool true" \
          "GOOGLE_ANALYTICS_ADID_COLLECTION_ENABLED bool false" \
          "GOOGLE_ANALYTICS_IDFV_COLLECTION_ENABLED bool false" \
          "GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_PERSONALIZATION_SIGNALS bool false"; do
          set -- $kv
          $PB -c "Delete :$1" "$APP_INFO" >/dev/null 2>&1 || true
          $PB -c "Add :$1 $2 $3" "$APP_INFO"
        done
      fi
    else
      python3 "$PY" patch-info "$APP_INFO" "$APP_ENV"
    fi
    got=$(pl_get "$APP_INFO" TashilEnv)
    [ "$got" = "$APP_ENV" ] || fail "TashilEnv in built Info.plist is '$got'."
    echo "[Tashil firebase-config] install OK: $DEST (project=$EXPECTED_PROJECT_ID) TashilEnv=$APP_ENV"
    ;;
  *)
    fail "usage: firebase_config.sh check|install"
    ;;
esac
