#!/usr/bin/env bash
# TAS-200: warm_web_cdn.sh requests the big build files and fails on a 404.
# Serves a fake build/web from a local python http.server. bash 3.2 compatible.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/scripts/warm_web_cdn.sh"
TMP="$(mktemp -d)"
fail() { echo "FAIL warm_web_cdn.test: $*" >&2; exit 1; }

mkdir -p "$TMP/web/assets/fonts" "$TMP/web/canvaskit"
echo '<html></html>' > "$TMP/web/index.html"
echo '// bootstrap' > "$TMP/web/flutter_bootstrap.js"
head -c 300000 /dev/zero > "$TMP/web/main.dart.js"
head -c 200000 /dev/zero > "$TMP/web/assets/fonts/MaterialIcons-Regular.otf"
head -c 1000 /dev/zero > "$TMP/web/assets/small.json"

PORT="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')"
(cd "$TMP/web" && exec python3 -m http.server "$PORT" --bind 127.0.0.1 >/dev/null 2>&1) &
SERVER=$!
disown "$SERVER" 2>/dev/null || true
trap 'kill $SERVER 2>/dev/null || true; rm -rf "$TMP"' EXIT
for _ in 1 2 3 4 5 6 7 8 9 10; do
  curl -s -o /dev/null "http://127.0.0.1:$PORT/index.html" && break
  sleep 0.3
done

out="$(bash "$SCRIPT" "http://127.0.0.1:$PORT" "$TMP/web" 2)" || fail "warm run failed: $out"
echo "$out" | grep -q "OK (http://127.0.0.1:$PORT)" || fail "no OK line"
[[ "$(echo "$out" | grep -c '^== round')" == "2" ]] || fail "expected 2 rounds"
echo "$out" | grep -q "main.dart.js" || fail "main.dart.js not requested"
echo "$out" | grep -q "assets/fonts/MaterialIcons-Regular.otf" || fail "big font not requested"
if echo "$out" | grep -q "assets/small.json"; then fail "small file should be skipped"; fi

rm "$TMP/web/main.dart.js"
if bash "$SCRIPT" "http://127.0.0.1:$PORT" "$TMP/web" 1 >/dev/null 2>&1; then
  fail "a missing main.dart.js (404) was not reported"
fi

if bash "$SCRIPT" >/dev/null 2>&1; then fail "no base URL should exit non-zero"; fi

echo "OK test/scripts/warm_web_cdn.test.sh"
