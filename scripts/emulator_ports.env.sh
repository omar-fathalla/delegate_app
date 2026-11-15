# TA-39: configurable Firebase emulator ports (sourced, not executed).
# Defaults match committed firebase.json (8080/9099/9199) plus hub 4400 and functions 5001.

LOCAL_CI_FIRESTORE_PORT="${LOCAL_CI_FIRESTORE_PORT:-8080}"
LOCAL_CI_FIRESTORE_HUB_PORT="${LOCAL_CI_FIRESTORE_HUB_PORT:-4400}"
LOCAL_CI_AUTH_PORT="${LOCAL_CI_AUTH_PORT:-9099}"
LOCAL_CI_STORAGE_PORT="${LOCAL_CI_STORAGE_PORT:-9199}"
LOCAL_CI_FUNCTIONS_PORT="${LOCAL_CI_FUNCTIONS_PORT:-5001}"

export LOCAL_CI_FIRESTORE_PORT
export LOCAL_CI_FIRESTORE_HUB_PORT
export LOCAL_CI_AUTH_PORT
export LOCAL_CI_STORAGE_PORT
export LOCAL_CI_FUNCTIONS_PORT

emulator_export_hosts() {
  export FIRESTORE_EMULATOR_HOST="127.0.0.1:${LOCAL_CI_FIRESTORE_PORT}"
  export FIREBASE_AUTH_EMULATOR_HOST="127.0.0.1:${LOCAL_CI_AUTH_PORT}"
  export FIREBASE_STORAGE_EMULATOR_HOST="127.0.0.1:${LOCAL_CI_STORAGE_PORT}"
  export FIREBASE_FUNCTIONS_EMULATOR_HOST="127.0.0.1:${LOCAL_CI_FUNCTIONS_PORT}"
  export FUNCTIONS_EMULATOR_HOST="127.0.0.1:${LOCAL_CI_FUNCTIONS_PORT}"
}

emulator_ports_all() {
  printf '%s\n' \
    "${LOCAL_CI_FIRESTORE_PORT}" \
    "${LOCAL_CI_FIRESTORE_HUB_PORT}" \
    "${LOCAL_CI_AUTH_PORT}" \
    "${LOCAL_CI_STORAGE_PORT}" \
    "${LOCAL_CI_FUNCTIONS_PORT}"
}

wait_emulator_ports_free() {
  local p i
  for i in 1 2 3 4 5 6 7 8; do
    local busy=0
    while IFS= read -r p; do
      if lsof -nP -iTCP:"${p}" -sTCP:LISTEN >/dev/null 2>&1; then
        busy=1
        break
      fi
    done < <(emulator_ports_all)
    if [[ "${busy}" -eq 0 ]]; then
      return 0
    fi
    sleep 2
  done
  return 0
}