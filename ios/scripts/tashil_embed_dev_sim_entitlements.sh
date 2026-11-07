#!/bin/sh
# Debug-dev + iphonesimulator only: re-sign Runner.app so embedded entitlements
# match Runner-dev.entitlements (Flutter --no-codesign / thin leaves empty dict).
set -eu

. "${SRCROOT:?}/scripts/tashil_dev_build_context.sh"

case "${EFFECTIVE_PLATFORM_NAME:-}" in
  -iphonesimulator) ;;
  *) exit 0 ;;
esac

tashil_is_dev_build || exit 0

APP="${TARGET_BUILD_DIR:?}/${WRAPPER_NAME:?}"
ENT_SRC="${SRCROOT}/Runner/Runner-dev.entitlements"
[ -f "$ENT_SRC" ] || exit 0
[ -d "$APP" ] || exit 0

TEAM="${DEVELOPMENT_TEAM:-}"
BUNDLE="${PRODUCT_BUNDLE_IDENTIFIER:-}"
[ -n "$TEAM" ] && [ -n "$BUNDLE" ] || exit 0

TMP_ENT="$(mktemp "${TMPDIR:-/tmp}/tashil-sim-ent.XXXXXX")"
trap 'rm -f "$TMP_ENT"' EXIT

sed \
  -e 's/\$(AppIdentifierPrefix)/'"${TEAM}"'./g' \
  -e 's/\$(PRODUCT_BUNDLE_IDENTIFIER)/'"${BUNDLE}"'/g' \
  "$ENT_SRC" >"$TMP_ENT"

/usr/bin/codesign --force --sign - --entitlements "$TMP_ENT" --deep "$APP"
