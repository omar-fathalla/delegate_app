#!/usr/bin/env bash
# TAS-107: port slots keep CI jobs and local sessions on the shared Mac apart.
# No emulator needed: checks the slot math, runner mapping, busy-slot skipping,
# the busy report and that emulators_exec.sh fails fast on a taken port.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }

# Fresh env: no inherited overrides.
for v in LOCAL_CI_FIRESTORE_PORT LOCAL_CI_FIRESTORE_HUB_PORT LOCAL_CI_AUTH_PORT LOCAL_CI_STORAGE_PORT \
  LOCAL_CI_FUNCTIONS_PORT LOCAL_CI_LOGGING_PORT LOCAL_CI_FIRESTORE_WEBSOCKET_PORT; do unset "$v"; done
# shellcheck disable=SC1091
source "$ROOT/scripts/emulator_ports.env.sh"
[[ "$EMULATOR_PORTS_EXPLICIT" == 0 ]] || fail "defaults counted as explicit"

# 1. slot math: base + slot*1000 + default % 1000, seven distinct ports.
emulator_use_slot 20000 3
want="23080 23400 23099 23199 23001 23500 23150"
got="$(emulator_ports_all | tr '\n' ' ' | sed 's/ $//')"
[[ "$got" == "$want" ]] || fail "slot 20000:3 = '$got', want '$want'"
[[ "$(emulator_ports_all | sort -u | wc -l | tr -d ' ')" == 7 ]] || fail "ports not distinct"
echo "ok: slot math"

# 2. runner names -> slots (the Mac's runners are 1, 2, 3).
[[ "$(emulator_runner_slot tashil-delegate-mac)" == 1 ]] || fail "bare runner"
[[ "$(emulator_runner_slot tashil-delegate-mac-2)" == 2 ]] || fail "runner -2"
[[ "$(emulator_runner_slot tashil-delegate-mac-3)" == 3 ]] || fail "runner -3"
s="$(emulator_runner_slot some-other-runner)"
[[ "$s" -ge 1 && "$s" -le 9 ]] || fail "hashed slot out of range: $s"
echo "ok: runner slots"

# 3. CI and local ranges never overlap the defaults or each other.
for slot in 1 2 3 4 5 6 7 8 9; do
  emulator_use_slot 20000 "$slot"; ci="$(emulator_ports_all)"
  emulator_use_slot 30000 "$slot"; loc="$(emulator_ports_all)"
  for p in $ci $loc; do
    case "$p" in 8080|4400|9099|9199|5001|4500|9150) fail "slot $slot hits default port $p" ;; esac
    [[ "$p" -lt 49152 ]] || fail "port $p in the ephemeral range"
  done
done
echo "ok: ranges"

# 4. a busy local slot is skipped, and the report names the holder.
emulator_pick_local_slot || fail "no free local slot at all"
first="$EMULATOR_PORT_SLOT_USED"; held="$LOCAL_CI_FIRESTORE_HUB_PORT"
python3 -c "import socket,time; s=socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); s.bind(('127.0.0.1', $held)); s.listen(1); time.sleep(60)" &
holder=$!
trap 'kill $holder 2>/dev/null || true' EXIT
for _ in 1 2 3 4 5 6 7 8 9 10; do lsof -nP -iTCP:"$held" -sTCP:LISTEN >/dev/null 2>&1 && break; sleep 0.3; done
emulator_pick_local_slot || fail "no slot after the busy one"
[[ "$EMULATOR_PORT_SLOT_USED" != "$first" ]] || fail "picked the busy slot $first"
echo "ok: busy slot $first skipped -> $EMULATOR_PORT_SLOT_USED"

base="${first%%:*}"; slot="${first##*:}"
emulator_use_slot "$base" "$slot"
report="$(emulator_ports_busy_report)"
[[ "$report" == *"port $held: pid $holder"* ]] || fail "report does not name pid $holder on $held: $report"
echo "ok: busy report names the holder"

# 5. emulators_exec.sh fails fast (no firebase start) on explicitly taken ports.
out="$(LOCAL_CI_FIRESTORE_PORT=$LOCAL_CI_FIRESTORE_PORT LOCAL_CI_FIRESTORE_HUB_PORT=$held \
  LOCAL_CI_AUTH_PORT=$LOCAL_CI_AUTH_PORT LOCAL_CI_STORAGE_PORT=$LOCAL_CI_STORAGE_PORT \
  LOCAL_CI_FUNCTIONS_PORT=$LOCAL_CI_FUNCTIONS_PORT LOCAL_CI_LOGGING_PORT=$LOCAL_CI_LOGGING_PORT \
  LOCAL_CI_FIRESTORE_WEBSOCKET_PORT=$LOCAL_CI_FIRESTORE_WEBSOCKET_PORT \
  FIREBASE_TOOLS_BIN=false bash "$ROOT/scripts/emulators_exec.sh" --only firestore true 2>&1)" \
  && fail "emulators_exec.sh ran on a busy port"
[[ "$out" == *"emulator ports busy"* && "$out" == *"pid $holder"* ]] || fail "unclear busy error: $out"
echo "ok: emulators_exec.sh fails fast and names pid $holder"
kill "$holder" 2>/dev/null || true
wait "$holder" 2>/dev/null || true

# 6. TAS-111: an orphaned "emulator" that ignores SIGTERM gets SIGKILLed, and
#    emulators_exec.sh clears its own leftovers after the run (keeping the exit code).
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/emu-orphan.XXXXXX")"
cat > "$SCRATCH/fake-emulator.py" <<'PY'
import signal, socket, sys, time
signal.signal(signal.SIGTERM, signal.SIG_IGN)
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", int(sys.argv[1]))); s.listen(1)
open(sys.argv[2], "w").write(str(__import__("os").getpid()))
time.sleep(120)
PY
# Double fork so the listener is re-parented to launchd/init (ppid 1), like a
# JVM left behind by firebase.
spawn_orphan() { ( python3 "$SCRATCH/fake-emulator.py" "$1" "$2" </dev/null >/dev/null 2>&1 & ); }
wait_listen() { for _ in $(seq 1 40); do lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1 && return 0; sleep 0.25; done; return 1; }
trap 'kill $holder 2>/dev/null || true; [[ -f $SCRATCH/pid ]] && kill -9 "$(cat "$SCRATCH/pid")" 2>/dev/null; rm -rf "$SCRATCH"' EXIT

emulator_pick_local_slot || fail "no free local slot for the orphan test"
port="$LOCAL_CI_FIRESTORE_HUB_PORT"
spawn_orphan "$port" "$SCRATCH/pid"
wait_listen "$port" || fail "fake orphan never listened on $port"
opid="$(cat "$SCRATCH/pid")"
[[ "$(ps -o ppid= -p "$opid" | tr -d ' ')" == 1 ]] || fail "fake orphan $opid is not re-parented to pid 1"
out="$(EMULATOR_KILL_GRACE_SECONDS=1 emulator_kill_orphans_on_ports 2>&1)"
kill -0 "$opid" 2>/dev/null && fail "orphan $opid survived: $out"
[[ "$out" == *"ignored SIGTERM, sending SIGKILL"* ]] || fail "no SIGKILL escalation: $out"
emulator_ports_free || fail "slot ports still busy after the kill"
echo "ok: orphan that ignores SIGTERM is SIGKILLed"

cat > "$SCRATCH/fake-firebase.sh" <<EOF
#!/usr/bin/env bash
( python3 "$SCRATCH/fake-emulator.py" "\$LOCAL_CI_FIRESTORE_PORT" "$SCRATCH/pid" </dev/null >/dev/null 2>&1 & )
for _ in \$(seq 1 40); do lsof -nP -iTCP:"\$LOCAL_CI_FIRESTORE_PORT" -sTCP:LISTEN >/dev/null 2>&1 && break; sleep 0.25; done
exit 3
EOF
chmod +x "$SCRATCH/fake-firebase.sh"
rm -f "$SCRATCH/pid"
set +e
out="$(EMULATOR_KILL_GRACE_SECONDS=1 FIREBASE_TOOLS_BIN="$SCRATCH/fake-firebase.sh" \
  bash "$ROOT/scripts/emulators_exec.sh" --only firestore true 2>&1)"
rc=$?
set -e
[[ "$rc" == 3 ]] || fail "emulators_exec.sh lost the exit code ($rc): $out"
[[ -f "$SCRATCH/pid" ]] || fail "fake firebase never started its emulator: $out"
fs_port="$LOCAL_CI_FIRESTORE_PORT" # exported above, so emulators_exec.sh uses these ports as given
kill -0 "$(cat "$SCRATCH/pid")" 2>/dev/null && fail "leftover emulator still running after emulators_exec.sh: $out"
lsof -nP -iTCP:"$fs_port" -sTCP:LISTEN >/dev/null 2>&1 && fail "port $fs_port still busy after emulators_exec.sh"
echo "ok: emulators_exec.sh clears its leftovers and keeps the exit code"

echo "ok: emulator port slot tests passed"
