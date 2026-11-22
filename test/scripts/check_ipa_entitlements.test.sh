#!/usr/bin/env bash
# TAS-212: check_ipa_entitlements.sh passes only aps-environment=production.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/scripts/ci/check_ipa_entitlements.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

plist() {
  local file="$1" body="$2"
  cat > "$file" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>$body</dict></plist>
EOF
}

plist "$TMP/prod.plist" '<key>aps-environment</key><string>production</string>'
plist "$TMP/dev.plist" '<key>aps-environment</key><string>development</string>'
plist "$TMP/none.plist" '<key>application-identifier</key><string>X.com.tashil.delegate</string>'

bash "$SCRIPT" "$TMP/prod.plist" >/dev/null

for bad in dev none; do
  if bash "$SCRIPT" "$TMP/$bad.plist" >/dev/null 2>&1; then
    echo "check_ipa_entitlements.test: FAIL: $bad.plist was accepted" >&2
    exit 1
  fi
done

if bash "$SCRIPT" "$TMP/missing.ipa" >/dev/null 2>&1; then
  echo "check_ipa_entitlements.test: FAIL: missing file was accepted" >&2
  exit 1
fi

echo "check_ipa_entitlements.test: OK"
