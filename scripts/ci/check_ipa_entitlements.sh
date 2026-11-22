#!/usr/bin/env bash
# TAS-21 / TAS-212: refuse a store build whose app cannot receive push.
#
# The App Store build of 19 Oct 2026 shipped without `aps-environment`, so no
# iOS user got any push. Run this on the exported .ipa before uploading:
#
#   bash scripts/ci/check_ipa_entitlements.sh build/ios/ipa/Runner.ipa
#
# It also accepts an entitlements .plist directly (used by the test):
#
#   bash scripts/ci/check_ipa_entitlements.sh path/to/entitlements.plist
#
# Exit 0 only when aps-environment == production. Prints the value found.
set -euo pipefail

INPUT="${1:?usage: check_ipa_entitlements.sh <app.ipa | entitlements.plist>}"
[[ -f "$INPUT" ]] || { echo "check_ipa_entitlements: no such file: $INPUT" >&2; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

case "$INPUT" in
  *.ipa)
    unzip -q "$INPUT" -d "$WORK/x"
    APP="$(find "$WORK/x/Payload" -maxdepth 1 -name '*.app' -type d | head -1)"
    [[ -n "$APP" ]] || { echo "check_ipa_entitlements: no Payload/*.app in $INPUT" >&2; exit 2; }
    codesign -d --entitlements :- "$APP" > "$WORK/ent.plist" 2>/dev/null || {
      echo "check_ipa_entitlements: could not read entitlements of $APP (unsigned?)" >&2
      exit 2
    }
    PLIST="$WORK/ent.plist"
    ;;
  *)
    PLIST="$INPUT"
    ;;
esac

VALUE="$(/usr/libexec/PlistBuddy -c 'Print :aps-environment' "$PLIST" 2>/dev/null || true)"
if [[ "$VALUE" == "production" ]]; then
  echo "check_ipa_entitlements: OK aps-environment=production"
  exit 0
fi
echo "check_ipa_entitlements: FAIL aps-environment='${VALUE:-<missing>}' (must be production for the App Store)" >&2
exit 1
