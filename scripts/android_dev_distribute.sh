#!/usr/bin/env bash
# Build dev-flavor release APK and upload to Firebase App Distribution (tashil-dev).
# No secrets in repo: uses local firebase login + optional env overrides.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ALLOWED_PROJECT="tashil-dev"
ALLOWED_APP_ID="1:582609039627:android:40c38c45d1bdb99add720e"

android_dev_distribute_refuse_target() {
  echo "android_dev_distribute: refused: Firebase project must be ${ALLOWED_PROJECT} and app id must be ${ALLOWED_APP_ID} (env overrides only)" >&2
  echo "android_dev_distribute: got project=${1:-<unset>} app=${2:-<unset>}" >&2
  exit 1
}

android_dev_distribute_is_forbidden_cli_override() {
  case "$1" in
    --project | --app | --projectId) return 0 ;;
    --project=* | --app=* | --projectId=*) return 0 ;;
    -P | -P*) return 0 ;;
    *) return 1 ;;
  esac
}

# No pass-through to firebase CLI (blocks -P/--project/--app/--projectId overrides).
android_dev_distribute_assert_no_extra_args() {
  local arg
  for arg in "$@"; do
    if android_dev_distribute_is_forbidden_cli_override "$arg"; then
      echo "android_dev_distribute: refused Firebase CLI target override in arguments: $arg" >&2
      echo "android_dev_distribute: pass-through extras are disabled; use only allowed env defaults" >&2
      exit 1
    fi
  done
  if [[ $# -gt 0 ]]; then
    echo "android_dev_distribute: refused unknown/extra arguments (pass-through disabled): $*" >&2
    exit 1
  fi
}

android_dev_distribute_assert_env_targets() {
  local project="${FIREBASE_ANDROID_DEV_PROJECT:-$ALLOWED_PROJECT}"
  local app="${FIREBASE_ANDROID_DEV_APP_ID:-$ALLOWED_APP_ID}"

  if [[ -n "${FIREBASE_ANDROID_DEV_PROJECT-}" && "$FIREBASE_ANDROID_DEV_PROJECT" != "$ALLOWED_PROJECT" ]]; then
    android_dev_distribute_refuse_target "$FIREBASE_ANDROID_DEV_PROJECT" "${FIREBASE_ANDROID_DEV_APP_ID:-}"
  fi
  if [[ -n "${FIREBASE_ANDROID_DEV_APP_ID-}" && "$FIREBASE_ANDROID_DEV_APP_ID" != "$ALLOWED_APP_ID" ]]; then
    android_dev_distribute_refuse_target "${FIREBASE_ANDROID_DEV_PROJECT:-}" "$FIREBASE_ANDROID_DEV_APP_ID"
  fi
  if [[ "$project" != "$ALLOWED_PROJECT" || "$app" != "$ALLOWED_APP_ID" ]]; then
    android_dev_distribute_refuse_target "$project" "$app"
  fi
}

android_dev_distribute_make_test_shim() {
  local shim_root="$1"
  mkdir -p "$shim_root"
  printf '%s\n' '#!/bin/sh' 'exit 0' >"$shim_root/flutter"
  printf '%s\n' '#!/bin/sh' 'exit 0' >"$shim_root/firebase"
  chmod +x "$shim_root/flutter" "$shim_root/firebase"
}

android_dev_distribute_self_check() {
  set +e
  local rc=0

  (
    FIREBASE_ANDROID_DEV_PROJECT=practice-firebase-72df1 \
      android_dev_distribute_assert_env_targets
  ) >/dev/null 2>&1
  if [[ $? -eq 0 ]]; then
    echo "android_dev_distribute self-check: expected refuse for bad env project" >&2
    rc=1
  fi

  (
    FIREBASE_ANDROID_DEV_APP_ID=1:0:android:bad \
      android_dev_distribute_assert_env_targets
  ) >/dev/null 2>&1
  if [[ $? -eq 0 ]]; then
    echo "android_dev_distribute self-check: expected refuse for bad env app id" >&2
    rc=1
  fi

  run_refuse() {
    local label="$1"
    shift
    set +e
  (
      android_dev_distribute_assert_no_extra_args "$@"
    ) >/dev/null 2>&1
    local r=$?
    set -e
    if [[ $r -eq 0 ]]; then
      echo "android_dev_distribute self-check: expected refuse for extra arg: $label" >&2
      rc=1
    fi
  }
  run_refuse "cli --project" --project wrong-project
  run_refuse "cli --project=" --project=practice-firebase-72df1
  run_refuse "cli --app" --app 1:1:android:evil
  run_refuse "cli --app=" --app=1:0:android:evil
  run_refuse "cli -P" -P practice-firebase-72df1
  run_refuse "cli -Pattached" -Ppractice-firebase-72df1
  run_refuse "cli --projectId" --projectId practice-firebase-72df1
  run_refuse "cli --projectId=" --projectId=practice-firebase-72df1

  if ! env -u FIREBASE_ANDROID_DEV_PROJECT -u FIREBASE_ANDROID_DEV_APP_ID \
    bash -c 'source "$1"; android_dev_distribute_assert_env_targets' bash "$ROOT/scripts/android_dev_distribute.sh"; then
    echo "android_dev_distribute self-check: allowed env defaults must pass" >&2
    rc=1
  fi

  local shim_root
  shim_root="$(mktemp -d "${TMPDIR:-/tmp}/android-dev-distribute-shim.XXXXXX")"
  android_dev_distribute_make_test_shim "$shim_root"
  mkdir -p "$ROOT/build/app/outputs/flutter-apk"
  : >"$ROOT/build/app/outputs/flutter-apk/app-dev-release.apk"

  if ! env -u FIREBASE_ANDROID_DEV_PROJECT -u FIREBASE_ANDROID_DEV_APP_ID \
    PATH="$shim_root:$PATH" ANDROID_DEV_DISTRIBUTE_TEST_SHIM=1 \
    bash "$ROOT/scripts/android_dev_distribute.sh" --dry-run >/dev/null 2>&1; then
    echo "android_dev_distribute self-check: shim --dry-run (no extras) must pass" >&2
    rc=1
  fi

  if ! env -u FIREBASE_ANDROID_DEV_PROJECT -u FIREBASE_ANDROID_DEV_APP_ID \
    PATH="$shim_root:$PATH" ANDROID_DEV_DISTRIBUTE_TEST_SHIM=1 \
    bash "$ROOT/scripts/android_dev_distribute.sh" --no-dry-run --yes >/dev/null 2>&1; then
    echo "android_dev_distribute self-check: shim --no-dry-run --yes (no extras) must pass" >&2
    rc=1
  fi

  rm -rf "$shim_root"
  rm -f "$ROOT/build/app/outputs/flutter-apk/app-dev-release.apk"

  if [[ $rc -ne 0 ]]; then
    exit 1
  fi
  echo "android_dev_distribute self-check: OK"
}

android_dev_distribute_main() {
  cd "$ROOT"

  local dry_run=1
  local yes=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --self-check)
        android_dev_distribute_self_check
        exit 0
        ;;
      --dry-run)
        dry_run=1
        shift
        ;;
      --no-dry-run)
        dry_run=0
        shift
        ;;
      --yes)
        yes=1
        shift
        ;;
      -h | --help)
        cat <<EOF
Usage: bash scripts/android_dev_distribute.sh [options]

Builds dev release APK. App Distribution upload is dry-run by default.
Firebase CLI pass-through arguments are not accepted (no --, -P, or --project overrides).

Options:
  --dry-run       Print upload plan only (default)
  --no-dry-run    Allow upload when combined with --yes
  --yes           Confirm Firebase App Distribution upload (--no-dry-run required)
  --self-check    Run refusal guard tests and exit
  -h, --help      Show this help

Allowed Firebase targets only (via env or script defaults):
  project: ${ALLOWED_PROJECT}  (FIREBASE_ANDROID_DEV_PROJECT)
  app:     ${ALLOWED_APP_ID}  (FIREBASE_ANDROID_DEV_APP_ID)
EOF
        exit 0
        ;;
      --)
        shift
        android_dev_distribute_assert_no_extra_args "$@"
        ;;
      -*)
        echo "android_dev_distribute: unknown option: $1" >&2
        exit 1
        ;;
      *)
        android_dev_distribute_assert_no_extra_args "$@"
        ;;
    esac
  done

  local project="${FIREBASE_ANDROID_DEV_PROJECT:-$ALLOWED_PROJECT}"
  local app_id="${FIREBASE_ANDROID_DEV_APP_ID:-$ALLOWED_APP_ID}"
  android_dev_distribute_assert_env_targets

  local apk="build/app/outputs/flutter-apk/app-dev-release.apk"
  local git_sha
  git_sha="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
  local release_notes="${RELEASE_NOTES:-Android dev $(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo manual)}"

  local test_shim=0
  if [[ "${ANDROID_DEV_DISTRIBUTE_TEST_SHIM:-}" == "1" ]]; then
    test_shim=1
  fi

  if [[ "$test_shim" -eq 0 ]]; then
    if ! command -v firebase >/dev/null 2>&1; then
      echo "android_dev_distribute: install Firebase CLI (https://firebase.google.com/docs/cli)" >&2
      exit 1
    fi

    echo "android_dev_distribute: flutter pub get"
    flutter pub get --enforce-lockfile

    echo "android_dev_distribute: building release dev APK (GIT_SHA=${git_sha})"
    flutter build apk --release --flavor dev \
      --dart-define=ENV=dev \
      --dart-define=GIT_SHA="${git_sha}"
  else
    mkdir -p "$(dirname "$apk")"
    : >"$apk"
    echo "android_dev_distribute: test shim active (skip flutter build)"
  fi

  [[ -f "$apk" ]] || { echo "android_dev_distribute: missing $apk" >&2; exit 1; }

  local upload_cmd=(
    firebase appdistribution:distribute "$apk"
    --app "$app_id"
    --project "$project"
    --release-notes "$release_notes"
  )

  if [[ "$dry_run" -eq 1 ]]; then
    echo "android_dev_distribute: dry-run (default): would run:"
    # bash 3.2 + set -u: safe expansion for possibly empty arrays
    printf '  %q\n' ${upload_cmd[@]+"${upload_cmd[@]}"}
    echo "android_dev_distribute: pass --no-dry-run --yes to upload"
    exit 0
  fi

  if [[ "$yes" -ne 1 ]]; then
    echo "android_dev_distribute: refused upload without --yes" >&2
    exit 1
  fi

  echo "android_dev_distribute: uploading to App Distribution (project=$project app=$app_id)"
  ${upload_cmd[@]+"${upload_cmd[@]}"}

  echo "android_dev_distribute: done"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  android_dev_distribute_main "$@"
fi