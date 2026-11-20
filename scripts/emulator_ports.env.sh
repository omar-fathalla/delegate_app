# TA-39: configurable Firebase emulator ports (sourced, not executed).
# Defaults match committed firebase.json plus hub 4400, functions 5001, logging 4500, ws 9150.
#
# Optional overrides (parallel local_ci / CI runs on one Mac):
#   LOCAL_CI_FIRESTORE_PORT          (default 8080)
#   LOCAL_CI_FIRESTORE_HUB_PORT      (default 4400)
#   LOCAL_CI_AUTH_PORT               (default 9099)
#   LOCAL_CI_STORAGE_PORT            (default 9199)
#   LOCAL_CI_FUNCTIONS_PORT          (default 5001)
#   LOCAL_CI_LOGGING_PORT            (default 4500)
#   LOCAL_CI_FIRESTORE_WEBSOCKET_PORT (default 9150)
#
# TAS-107: CI and local sessions share one Mac, so emulators_exec.sh no longer
# uses these defaults unless asked to (EMULATOR_PORT_SLOT=off). It picks a
# port slot instead: every port is BASE + slot*1000 + (default % 1000).
#   CI (GITHUB_ACTIONS=true): base 20000, slot from RUNNER_NAME
#     (tashil-delegate-mac -> 1, tashil-delegate-mac-N -> N). A runner runs one
#     job at a time, so two jobs never share ports.
#   Local: base 30000, first slot 1..9 whose seven ports are all free.
# Explicit LOCAL_CI_* overrides always win.

# Set before the defaults below so callers can tell an override from a default.
if [[ -n "${LOCAL_CI_FIRESTORE_PORT:-}" ]]; then
  EMULATOR_PORTS_EXPLICIT=1
else
  EMULATOR_PORTS_EXPLICIT=0
fi

LOCAL_CI_FIRESTORE_PORT="${LOCAL_CI_FIRESTORE_PORT:-8080}"
LOCAL_CI_FIRESTORE_HUB_PORT="${LOCAL_CI_FIRESTORE_HUB_PORT:-4400}"
LOCAL_CI_AUTH_PORT="${LOCAL_CI_AUTH_PORT:-9099}"
LOCAL_CI_STORAGE_PORT="${LOCAL_CI_STORAGE_PORT:-9199}"
LOCAL_CI_FUNCTIONS_PORT="${LOCAL_CI_FUNCTIONS_PORT:-5001}"
LOCAL_CI_LOGGING_PORT="${LOCAL_CI_LOGGING_PORT:-4500}"
LOCAL_CI_FIRESTORE_WEBSOCKET_PORT="${LOCAL_CI_FIRESTORE_WEBSOCKET_PORT:-9150}"

export LOCAL_CI_FIRESTORE_PORT
export LOCAL_CI_FIRESTORE_HUB_PORT
export LOCAL_CI_AUTH_PORT
export LOCAL_CI_STORAGE_PORT
export LOCAL_CI_FUNCTIONS_PORT
export LOCAL_CI_LOGGING_PORT
export LOCAL_CI_FIRESTORE_WEBSOCKET_PORT

# Unset all LOCAL_CI_* overrides (e.g. default-port smoke under custom local_ci env).
emulator_unset_local_ci_ports() {
  unset LOCAL_CI_FIRESTORE_PORT \
    LOCAL_CI_FIRESTORE_HUB_PORT \
    LOCAL_CI_AUTH_PORT \
    LOCAL_CI_STORAGE_PORT \
    LOCAL_CI_FUNCTIONS_PORT \
    LOCAL_CI_LOGGING_PORT \
    LOCAL_CI_FIRESTORE_WEBSOCKET_PORT || true
}

emulator_export_hosts() {
  export FIRESTORE_EMULATOR_HOST="127.0.0.1:${LOCAL_CI_FIRESTORE_PORT}"
  export FIREBASE_AUTH_EMULATOR_HOST="127.0.0.1:${LOCAL_CI_AUTH_PORT}"
  export FIREBASE_STORAGE_EMULATOR_HOST="127.0.0.1:${LOCAL_CI_STORAGE_PORT}"
  export FIREBASE_FUNCTIONS_EMULATOR_HOST="127.0.0.1:${LOCAL_CI_FUNCTIONS_PORT}"
  export FUNCTIONS_EMULATOR_HOST="127.0.0.1:${LOCAL_CI_FUNCTIONS_PORT}"
  export FIRESTORE_EMULATOR_WEBSOCKET_PORT="${LOCAL_CI_FIRESTORE_WEBSOCKET_PORT}"
  export FIREBASE_LOGGING_EMULATOR_HOST="127.0.0.1:${LOCAL_CI_LOGGING_PORT}"
}

emulator_ports_all() {
  printf '%s\n' \
    "${LOCAL_CI_FIRESTORE_PORT}" \
    "${LOCAL_CI_FIRESTORE_HUB_PORT}" \
    "${LOCAL_CI_AUTH_PORT}" \
    "${LOCAL_CI_STORAGE_PORT}" \
    "${LOCAL_CI_FUNCTIONS_PORT}" \
    "${LOCAL_CI_LOGGING_PORT}" \
    "${LOCAL_CI_FIRESTORE_WEBSOCKET_PORT}"
}

# 0 when nothing listens on any of the seven ports.
emulator_ports_free() {
  local p
  while IFS= read -r p; do
    if lsof -nP -iTCP:"${p}" -sTCP:LISTEN >/dev/null 2>&1; then
      return 1
    fi
  done < <(emulator_ports_all)
  return 0
}

# Waits up to ~16 s for the ports to be released. Returns 1 if still busy
# (it used to return 0 either way, so callers never saw the conflict).
wait_emulator_ports_free() {
  local i
  for i in 1 2 3 4 5 6 7 8; do
    emulator_ports_free && return 0
    sleep 2
  done
  return 1
}

# Sets all seven LOCAL_CI_* ports from a base and a slot (1..9).
emulator_use_slot() {
  local base="$1" slot="$2"
  local off=$((base + slot * 1000))
  LOCAL_CI_FIRESTORE_PORT=$((off + 80))
  LOCAL_CI_FIRESTORE_HUB_PORT=$((off + 400))
  LOCAL_CI_AUTH_PORT=$((off + 99))
  LOCAL_CI_STORAGE_PORT=$((off + 199))
  LOCAL_CI_FUNCTIONS_PORT=$((off + 1))
  LOCAL_CI_LOGGING_PORT=$((off + 500))
  LOCAL_CI_FIRESTORE_WEBSOCKET_PORT=$((off + 150))
  export LOCAL_CI_FIRESTORE_PORT LOCAL_CI_FIRESTORE_HUB_PORT LOCAL_CI_AUTH_PORT \
    LOCAL_CI_STORAGE_PORT LOCAL_CI_FUNCTIONS_PORT LOCAL_CI_LOGGING_PORT \
    LOCAL_CI_FIRESTORE_WEBSOCKET_PORT
  EMULATOR_PORT_SLOT_USED="${base}:${slot}"
  export EMULATOR_PORT_SLOT_USED
}

# Slot 1..9 for a runner name: trailing -N wins, the bare name is 1, anything
# else is hashed so unknown runners still spread out.
emulator_runner_slot() {
  local name="${1:-}"
  if [[ "${name}" =~ -([1-9])$ ]]; then
    echo "${BASH_REMATCH[1]}"
  elif [[ "${name}" == "tashil-delegate-mac" || -z "${name}" ]]; then
    echo 1
  else
    echo $(( $(printf '%s' "${name}" | cksum | cut -d' ' -f1) % 9 + 1 ))
  fi
}

# First local slot (base 30000) whose seven ports are all free; returns 1 if none.
emulator_pick_local_slot() {
  local slot
  for slot in 1 2 3 4 5 6 7 8 9; do
    emulator_use_slot 30000 "${slot}"
    if emulator_ports_free; then
      return 0
    fi
  done
  return 1
}

# Prints who holds each busy port (pid, parent, user, age, cwd, command).
emulator_ports_busy_report() {
  local p pid
  while IFS= read -r p; do
    for pid in $(lsof -nP -iTCP:"${p}" -sTCP:LISTEN -t 2>/dev/null | sort -u); do
      local ppid user etime cmd cwd
      ppid="$(ps -o ppid= -p "${pid}" 2>/dev/null | tr -d ' ')"
      user="$(ps -o user= -p "${pid}" 2>/dev/null | tr -d ' ')"
      etime="$(ps -o etime= -p "${pid}" 2>/dev/null | tr -d ' ')"
      cmd="$(ps -o command= -p "${pid}" 2>/dev/null | cut -c1-140)"
      cwd="$(lsof -a -p "${pid}" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -1)"
      local tag=""
      [[ "${ppid}" == 1 ]] && tag=", ORPHANED"
      echo "  port ${p}: pid ${pid} (parent ${ppid}${tag}) user ${user} up ${etime}"
      echo "    cwd: ${cwd:-?}"
      echo "    cmd: ${cmd}"
    done
  done < <(emulator_ports_all)
}

# Kills emulator processes owned by this user that hold our ports and whose
# parent is gone (ppid 1): leftovers of a cancelled or crashed run. Never
# touches a process whose parent is alive, or another user's process.
emulator_kill_orphans_on_ports() {
  local p pid killed=0 me
  me="$(id -un)"
  while IFS= read -r p; do
    for pid in $(lsof -nP -iTCP:"${p}" -sTCP:LISTEN -t 2>/dev/null | sort -u); do
      local ppid user cmd
      ppid="$(ps -o ppid= -p "${pid}" 2>/dev/null | tr -d ' ')"
      user="$(ps -o user= -p "${pid}" 2>/dev/null | tr -d ' ')"
      cmd="$(ps -o command= -p "${pid}" 2>/dev/null)"
      if [[ "${ppid}" == 1 && "${user}" == "${me}" && "${cmd}" == *emulator* ]]; then
        echo "emulator ports: killing orphaned emulator pid ${pid} on port ${p}" >&2
        kill "${pid}" 2>/dev/null && killed=1
      fi
    done
  done < <(emulator_ports_all)
  [[ "${killed}" -eq 1 ]] && sleep 3
  return 0
}
