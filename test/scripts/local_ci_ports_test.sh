#!/usr/bin/env bash
# TA-39: delegates to real bind test (kept for callers referencing this path).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec bash "$ROOT/test/scripts/emulator_ports_bind.test.sh"