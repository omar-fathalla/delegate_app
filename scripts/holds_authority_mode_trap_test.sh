#!/usr/bin/env bash
# Ensures patch_mode's RETURN trap does not trip set -u or exit 1 after
# the function returns (L5). No network, no gcloud.
set -euo pipefail
export TZ=Africa/Cairo

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/holds-mode-trap-test.XXXXXX")"
cleanup() { rm -rf "$tmp_dir"; }
trap cleanup EXIT

err_file="$tmp_dir/stderr.txt"
# Recreate the patch_mode / apply_mode / status_all shape from the flip script.
run_sim() {
  set -euo pipefail
  patch_mode() {
    local name="$1"
    local patch_file resp_file
    patch_file="$(mktemp "$tmp_dir/holds-mode-patch.XXXXXX.json")"
    resp_file="$(mktemp "$tmp_dir/holds-mode-patch-resp.XXXXXX.json")"
    chmod 600 "$patch_file" "$resp_file"
    printf '%s\n' '{"environmentVariables":{}}' > "$patch_file"
    trap 'rm -f "${patch_file:-}" "${resp_file:-}"; trap - RETURN' RETURN
    # Successful body; RETURN must clean up and leave set -u intact.
    echo "patched $name"
    return 0
  }
  status_all() {
    echo "status_all"
    return 0
  }
  apply_mode() {
    local fn
    for fn in setDelegateHold startBillingCycle finalizeSubscriptionRenewalOnStatus; do
      patch_mode "$fn"
    done
    status_all
  }
  apply_mode
}

if ! run_sim >"$tmp_dir/stdout.txt" 2>"$err_file"; then
  echo "FAIL: simulation exited non-zero" >&2
  cat "$err_file" >&2
  exit 1
fi
if grep -q 'unbound variable' "$err_file"; then
  echo "FAIL: unbound variable after RETURN trap" >&2
  cat "$err_file" >&2
  exit 1
fi
# Temp patch files from the simulation must be gone.
leftover="$(find "$tmp_dir" -name 'holds-mode-patch*' -print || true)"
if [[ -n "$leftover" ]]; then
  echo "FAIL: patch temp files not removed:" >&2
  echo "$leftover" >&2
  exit 1
fi
if ! grep -q 'status_all' "$tmp_dir/stdout.txt"; then
  echo "FAIL: status_all did not run" >&2
  exit 1
fi
echo "holds_authority_mode RETURN trap test OK"
exit 0
