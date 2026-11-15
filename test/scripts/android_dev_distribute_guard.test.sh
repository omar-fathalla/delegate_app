#!/usr/bin/env bash
# TA-49: prove android_dev_distribute.sh refuses wrong Firebase project/app targets.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

SCRIPT="$ROOT/scripts/android_dev_distribute.sh"
[[ -f "$SCRIPT" ]]

expect_fail() {
  local label="$1"
  shift
  set +e
  "$@"
  local rc=$?
  set -e
  if [[ $rc -eq 0 ]]; then
    echo "android_dev_distribute_guard: FAIL: expected refusal for $label" >&2
    exit 1
  fi
}

run_guard_suite() {
  local bash_bin="$1"
  local tag="$2"
  local script="${3:-$ROOT/scripts/android_dev_distribute.sh}"
  local suite_root="$ROOT"
  local shim_path="${suite_root}/.android-dev-distribute-shim"
  if [[ "$script" == /repo/* ]]; then
    shim_path="/repo/.android-dev-distribute-shim"
  fi

  "$bash_bin" "$script" --self-check

  expect_fail "$tag bad env project" \
    env FIREBASE_ANDROID_DEV_PROJECT=practice-firebase-72df1 \
    "$bash_bin" "$script" --dry-run

  expect_fail "$tag bad env app" \
    env FIREBASE_ANDROID_DEV_APP_ID=1:999:android:bad \
    "$bash_bin" "$script" --dry-run

  expect_fail "$tag cli --project" \
    "$bash_bin" "$script" --dry-run --project practice-firebase-72df1

  expect_fail "$tag cli --project=" \
    "$bash_bin" "$script" --dry-run --project=practice-firebase-72df1

  expect_fail "$tag cli --app" \
    "$bash_bin" "$script" --dry-run --app 1:0:android:evil

  expect_fail "$tag cli --app=" \
    "$bash_bin" "$script" --dry-run --app=1:0:android:evil

  expect_fail "$tag cli -P" \
    "$bash_bin" "$script" --dry-run -- -P practice-firebase-72df1

  expect_fail "$tag cli -Pattached" \
    "$bash_bin" "$script" --dry-run -- -Ppractice-firebase-72df1

  expect_fail "$tag cli --projectId" \
    "$bash_bin" "$script" --dry-run -- --projectId practice-firebase-72df1

  expect_fail "$tag cli --projectId=" \
    "$bash_bin" "$script" --dry-run -- --projectId=practice-firebase-72df1

  expect_fail "$tag positional extra" \
    "$bash_bin" "$script" --dry-run -- --groups testers

  local shim_root="${suite_root}/.android-dev-distribute-shim"
  rm -rf "$shim_root"
  mkdir -p "$shim_root"
  printf '%s\n' '#!/bin/sh' 'exit 0' >"$shim_root/flutter"
  printf '%s\n' '#!/bin/sh' 'exit 0' >"$shim_root/firebase"
  chmod +x "$shim_root/flutter" "$shim_root/firebase"
  mkdir -p "${suite_root}/build/app/outputs/flutter-apk"
  : >"${suite_root}/build/app/outputs/flutter-apk/app-dev-release.apk"

  if ! env -u FIREBASE_ANDROID_DEV_PROJECT -u FIREBASE_ANDROID_DEV_APP_ID \
    PATH="${shim_path}:$PATH" ANDROID_DEV_DISTRIBUTE_TEST_SHIM=1 \
    "$bash_bin" "$script" --dry-run >/dev/null 2>&1; then
    echo "android_dev_distribute_guard: FAIL: $tag shim dry-run (no extras)" >&2
    rm -rf "$shim_root"
    rm -f "${suite_root}/build/app/outputs/flutter-apk/app-dev-release.apk"
    exit 1
  fi

  if ! env -u FIREBASE_ANDROID_DEV_PROJECT -u FIREBASE_ANDROID_DEV_APP_ID \
    PATH="${shim_path}:$PATH" ANDROID_DEV_DISTRIBUTE_TEST_SHIM=1 \
    "$bash_bin" "$script" --no-dry-run --yes >/dev/null 2>&1; then
    echo "android_dev_distribute_guard: FAIL: $tag shim upload (no extras)" >&2
    rm -rf "$shim_root"
    rm -f "${suite_root}/build/app/outputs/flutter-apk/app-dev-release.apk"
    exit 1
  fi

  rm -rf "$shim_root"
  rm -f "${suite_root}/build/app/outputs/flutter-apk/app-dev-release.apk"
}

run_guard_suite bash "bash"

if command -v docker >/dev/null 2>&1; then
  docker_cmd=(docker)
  if ! docker info >/dev/null 2>&1; then
    if sudo docker info >/dev/null 2>&1; then
      docker_cmd=(sudo docker)
    fi
  fi
  if "${docker_cmd[@]}" info >/dev/null 2>&1; then
    "${docker_cmd[@]}" pull -q bash:3.2 >/dev/null 2>&1 || "${docker_cmd[@]}" pull bash:3.2
    bash32_wrapper="$(mktemp "${TMPDIR:-/tmp}/bash32-wrapper.XXXXXX")"
    # Executable wrapper (not a shell function) so env VAR=... prefix works in expect_fail.
    {
      echo '#!/usr/bin/env bash'
      echo 'set -euo pipefail'
      echo 'args=()'
      printf 'args+=(%q) ' "${docker_cmd[@]}"
      echo
      echo "args+=(run --rm -i -v \"${ROOT}:/repo:rw\" -w /repo -e HOME=/tmp)"
      cat <<'WRAPPER'
[[ -n "${FIREBASE_ANDROID_DEV_PROJECT-}" ]] && args+=(-e "FIREBASE_ANDROID_DEV_PROJECT=${FIREBASE_ANDROID_DEV_PROJECT}")
[[ -n "${FIREBASE_ANDROID_DEV_APP_ID-}" ]] && args+=(-e "FIREBASE_ANDROID_DEV_APP_ID=${FIREBASE_ANDROID_DEV_APP_ID}")
[[ -n "${ANDROID_DEV_DISTRIBUTE_TEST_SHIM-}" ]] && args+=(-e "ANDROID_DEV_DISTRIBUTE_TEST_SHIM=${ANDROID_DEV_DISTRIBUTE_TEST_SHIM}")
[[ -n "${PATH-}" ]] && args+=(-e "PATH=${PATH}")
args+=(bash:3.2 bash "$@")
exec "${args[@]}"
WRAPPER
    } >"$bash32_wrapper"
    chmod +x "$bash32_wrapper"
    run_guard_suite "$bash32_wrapper" "bash-3.2" "/repo/scripts/android_dev_distribute.sh"
    rm -f "$bash32_wrapper"
  else
    echo "android_dev_distribute_guard: WARN: docker daemon unavailable; skipped bash 3.2 suite" >&2
  fi
else
  echo "android_dev_distribute_guard: WARN: docker not available; skipped bash 3.2 suite" >&2
fi

echo "android_dev_distribute_guard: OK"