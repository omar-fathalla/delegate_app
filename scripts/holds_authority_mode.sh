#!/usr/bin/env bash
# Flip or roll back HOLDS_AUTHORITY_MODE on already-deployed Cloud Functions.
# tashil-dev only. PATCHes environment variables; does not upload source.
# Never touches suspendExpiredSubscriptions.
#
# Usage:
#   bash scripts/holds_authority_mode.sh status   --project tashil-dev
#   bash scripts/holds_authority_mode.sh flip     --project tashil-dev
#   bash scripts/holds_authority_mode.sh rollback --project tashil-dev
#
# Flip sets HOLDS_AUTHORITY_MODE=authoritative on the allowlisted functions.
# Rollback sets HOLDS_AUTHORITY_MODE=shadow (one step back). holdsMode() also
# treats a missing/typo value as shadow, but the script writes "shadow"
# explicitly so `status` shows the intended mode.
set -euo pipefail

export TZ=Africa/Cairo

ALLOWED_PROJECT="tashil-dev"
# Writers that read process.env.HOLDS_AUTHORITY_MODE on tashil-dev.
# auditDelegateHoldShadow only logs and is left unchanged.
# suspendExpiredSubscriptions must never be in this list or deployed here.
ALLOWED_FUNCTIONS=(setDelegateHold startBillingCycle)
BLOCKED_FUNCTIONS=(suspendExpiredSubscriptions)
REGION="${REGION:-us-central1}"
GCLOUD="${GCLOUD:-gcloud}"
if [[ ! -x "$(command -v "$GCLOUD" 2>/dev/null || true)" ]]; then
  if [[ -x /Users/fathalla/google-cloud-sdk/bin/gcloud ]]; then
    GCLOUD=/Users/fathalla/google-cloud-sdk/bin/gcloud
  fi
fi

usage() {
  sed -n '2,16p' "$0" | tr -d '#'
  exit 2
}

CMD=""
PROJECT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    status|flip|rollback) CMD="$1"; shift ;;
    --project) PROJECT="${2:-}"; shift 2 ;;
    --project=*) PROJECT="${1#--project=}"; shift ;;
    -h|--help) usage ;;
    *) echo "unknown argument: $1" >&2; usage ;;
  esac
done

if [[ -z "$CMD" || -z "$PROJECT" ]]; then
  usage
fi
if [[ "$PROJECT" != "$ALLOWED_PROJECT" ]]; then
  echo "refusing project '$PROJECT' (only $ALLOWED_PROJECT is allowed)" >&2
  exit 2
fi

gcloud_cmd() {
  env -u CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT \
    "$GCLOUD" --project="$PROJECT" "$@"
}

api_get() {
  local name="$1"
  local token
  token="$(gcloud_cmd auth print-access-token)"
  curl -sS -f -H "Authorization: Bearer ${token}" \
    "https://cloudfunctions.googleapis.com/v1/projects/${PROJECT}/locations/${REGION}/functions/${name}"
}

print_mode() {
  local name="$1"
  local json mode
  json="$(api_get "$name")"
  mode="$(python3 -c 'import json,sys; d=json.load(sys.stdin); print((d.get("environmentVariables") or {}).get("HOLDS_AUTHORITY_MODE") or "(unset, defaults to shadow)")' <<<"$json")"
  local status updated
  status="$(python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("status") or "?")' <<<"$json")"
  updated="$(python3 -c 'import json,sys; from datetime import datetime,timezone,timedelta
d=json.load(sys.stdin)
t=d.get("updateTime") or ""
print(t)
' <<<"$json")"
  echo "  ${name}: status=${status} HOLDS_AUTHORITY_MODE=${mode} updateTime=${updated}"
}

status_all() {
  echo "HOLDS_AUTHORITY_MODE on ${PROJECT} (${REGION}) at $(date '+%Y-%m-%d %H:%M:%S %Z')"
  local fn
  for fn in "${ALLOWED_FUNCTIONS[@]}"; do
    print_mode "$fn"
  done
}

wait_op() {
  local op_name="$1"
  local token
  token="$(gcloud_cmd auth print-access-token)"
  local i
  for i in $(seq 1 60); do
    local body
    body="$(curl -sS -f -H "Authorization: Bearer ${token}" \
      "https://cloudfunctions.googleapis.com/v1/${op_name}")"
    local done err
    done="$(python3 -c 'import json,sys; d=json.load(sys.stdin); print("true" if d.get("done") else "false")' <<<"$body")"
    if [[ "$done" == "true" ]]; then
      err="$(python3 -c 'import json,sys; d=json.load(sys.stdin); e=d.get("error"); print(e if e else "")' <<<"$body")"
      if [[ -n "$err" && "$err" != "" && "$err" != "None" ]]; then
        echo "operation failed: $err" >&2
        exit 1
      fi
      return 0
    fi
    sleep 2
  done
  echo "timed out waiting for ${op_name}" >&2
  exit 1
}

patch_mode() {
  local name="$1"
  local value="$2"
  # Refuse if the name is blocked, even if a caller edits the list poorly.
  local blocked
  for blocked in "${BLOCKED_FUNCTIONS[@]}"; do
    if [[ "$name" == "$blocked" ]]; then
      echo "refusing to touch ${name}" >&2
      exit 2
    fi
  done
  local json token
  json="$(api_get "$name")"
  python3 -c '
import json,sys
value=sys.argv[1]
# GCLOUD_PROJECT (and a few others) are reserved: including them in a
# PATCH returns HTTP 400. The system re-injects reserved keys at runtime.
RESERVED = {
    "GCLOUD_PROJECT", "FUNCTION_TARGET", "FUNCTION_SIGNATURE_TYPE",
    "FUNCTION_NAME", "K_SERVICE", "K_REVISION", "K_CONFIGURATION", "PORT",
}
d=json.load(sys.stdin)
env={k:v for k,v in (d.get("environmentVariables") or {}).items() if k not in RESERVED}
env["HOLDS_AUTHORITY_MODE"]=value
json.dump({"environmentVariables": env}, sys.stdout)
' "$value" <<<"$json" > "/tmp/holds-mode-patch-${name}.json"
  token="$(gcloud_cmd auth print-access-token)"
  local http_code resp
  http_code="$(curl -sS -o /tmp/holds-mode-patch-resp-${name}.json -w "%{http_code}"     -H "Authorization: Bearer ${token}"     -H "Content-Type: application/json"     -X PATCH     -d @"/tmp/holds-mode-patch-${name}.json"     "https://cloudfunctions.googleapis.com/v1/projects/${PROJECT}/locations/${REGION}/functions/${name}?updateMask=environmentVariables")"
  rm -f "/tmp/holds-mode-patch-${name}.json"
  resp="$(cat /tmp/holds-mode-patch-resp-${name}.json)"
  rm -f "/tmp/holds-mode-patch-resp-${name}.json"
  if [[ "$http_code" != "200" && "$http_code" != "201" ]]; then
    echo "PATCH ${name} failed HTTP ${http_code}: $(python3 -c 'import json,sys
try:
 d=json.load(sys.stdin); e=d.get("error") or d; print(e.get("message") if isinstance(e,dict) else e)
except Exception:
 print(sys.stdin if False else "unreadable body")
' <<<"$resp")" >&2
    exit 1
  fi
  local op
  op="$(python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("name") or "")' <<<"$resp")"
  if [[ -z "$op" ]]; then
    echo "no operation name in PATCH response for ${name}: $resp" >&2
    exit 1
  fi
  echo "  waiting for ${name} operation..."
  wait_op "$op"
}

apply_mode() {
  local value="$1"
  local label="$2"
  echo "${label} HOLDS_AUTHORITY_MODE=${value} on ${PROJECT} (no source upload)"
  local fn
  for fn in "${ALLOWED_FUNCTIONS[@]}"; do
    echo "  patching ${fn}..."
    patch_mode "$fn" "$value"
  done
  status_all
}

case "$CMD" in
  status) status_all ;;
  flip) apply_mode "authoritative" "FLIP" ;;
  rollback) apply_mode "shadow" "ROLLBACK" ;;
  *) usage ;;
esac
