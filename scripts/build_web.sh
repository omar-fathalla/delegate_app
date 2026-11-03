#!/usr/bin/env bash
# Build Flutter web for an environment: scripts/build_web.sh [prod|dev]
# prod: plain `flutter build web --release` (output unchanged).
# dev:  ENV=dev build, then swaps the Maps JS key in build/web/index.html
#       for the tashil-dev key from lib/core/config/maps_keys.dart.
set -euo pipefail
ENV_NAME="${1:-prod}"
cd "$(dirname "$0")/.."
key_of() { grep -A1 "static const String $1" lib/core/config/maps_keys.dart | grep -o "'[^']*'" | tr -d "'"; }
case "$ENV_NAME" in
  prod)
    flutter build web --release
    ;;
  dev)
    flutter build web --release --dart-define=ENV=dev
    PROD_KEY="$(key_of prodMapsJs)"; DEV_KEY="$(key_of devMapsPlaces)"
    [ -n "$PROD_KEY" ] && [ -n "$DEV_KEY" ] || { echo "maps keys not found" >&2; exit 1; }
    sed -i.bak "s/${PROD_KEY}/${DEV_KEY}/g" build/web/index.html && rm build/web/index.html.bak
    if grep -rq "$PROD_KEY" build/web; then echo "prod Maps key still in dev build" >&2; exit 1; fi
    ;;
  *) echo "usage: $0 [prod|dev]" >&2; exit 2 ;;
esac
