#!/usr/bin/env bash
# Build dev-flavor release APK and upload to Firebase App Distribution (tashil-dev).
# No secrets in repo: uses local firebase login + optional env overrides.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ALLOWED_PROJECT="tashil-dev"
ALLOWED_APP_ID="1:582609039627:android:40c38c45d1bdb99add720e"

android_dev_distribute_refuse_target() {
  echo "android_dev_distribute: refused: Firebase project must be ${ALLOWED_PROJECT} and app id must be ${ALLOWED_APP_ID} (env overrides and \"\$@\" included)" >&2
  echo "android_dev_distribute: got project=${1:-<unset>} app=${2:-<unset>}" >&2
  exit 1
}

# Validate env defaults/overrides and any --project / --app in extra Firebase CLI args.
android_dev_distribute_assert_firebase_target() {
  local project app
  project="${FIREBASE_ANDROID_DEV_PROJECT:-$ALLOWED_PROJECT}"
  app="${FIREBASE_ANDROID_DEV_APP_ID:-$ALLOWED_APP_ID}"

  if [[ -n "${FIREBASE_ANDROID_DEV_PROJECT-}" && "$FIREBASE_ANDROID_DEV_PROJECT" != "$ALLOWED_PROJECT" ]]; then
    android_dev_distribute_refuse_target "$FIREBASE_ANDROID_DEV_PROJECT" "${FIREBASE_ANDROID_DEV_APP_ID:-}"
    return 1
  fi
  if [[ -n "${FIREBASE_ANDROID_DEV_APP_ID-}" && "$FIREBASE_ANDROID_DEV_APP_ID" != "$ALLOWED_APP_ID" ]]; then
    android_dev_distribute_refuse_target "${FIREBASE_ANDROID_DEV_PROJECT:-}" "$FIREBASE_ANDROID_DEV_APP_ID"
    return 1
  fi

  local -a extra=()
  if [[ $# -gt 0 ]]; then
    extra=("$@")
  fi
  local i=0
  while (( i < ${#extra[@]} )); do
    local arg="${extra[i]}"
    case "$arg" in
      --project)
        ((++i))
        if (( i >= ${#extra[@]} )); then
          echo "android_dev_distribute: --project requires a value" >&2
          exit 1
        fi
        project="${extra[i]}"
        ;;
      --project=*)
        project="${arg#--project=}"
        ;;
      --app)
        ((++i))
        if (( i >= ${#extra[@]} )); then
          echo "android_dev_distribute: --app requires a value" >&2
          exit 1
        fi
        app="${extra[i]}"
        ;;
      --app=*)
        app="${arg#--app=}"
        ;;
    esac
    ((++i))
  done

  if [[ "$project" != "$ALLOWED_PROJECT" || "$app" != "$ALLOWED_APP_ID" ]]; then
    android_dev_distribute_refuse_target "$project" "$app"
  fi
}

android_dev_distribute_self_check() {
  set +e
  local rc=0

  (
    FIREBASE_ANDROID_DEV_PROJECT=practice-firebase-72df1 \
      android_dev_distribute_assert_firebase_target
  ) >/dev/null 2>&1
  if [[ $? -eq 0 ]]; then
    echo "android_dev_distribute self-check: expected refuse for bad env project" >&2
    rc=1
  fi

  (
    FIREBASE_ANDROID_DEV_APP_ID=1:0:android:bad \
      android_dev_distribute_assert_firebase_target
  ) >/dev/null 2>&1
  if [[ $? -eq 0 ]]; then
    echo "android_dev_distribute self-check: expected refuse for bad env app id" >&2
    rc=1
  fi

  (
    android_dev_distribute_assert_firebase_target --project wrong-project
  ) >/dev/null 2>&1
  if [[ $? -eq 0 ]]; then
    echo "android_dev_distribute self-check: expected refuse for bad --project" >&2
    rc=1
  fi

  (
    android_dev_distribute_assert_firebase_target --app 1:1:android:evil
  ) >/dev/null 2>&1
  if [[ $? -eq 0 ]]; then
    echo "android_dev_distribute self-check: expected refuse for bad --app" >&2
    rc=1
  fi

  if ! env -u FIREBASE_ANDROID_DEV_PROJECT -u FIREBASE_ANDROID_DEV_APP_ID \
    bash -c 'source "$1"; android_dev_distribute_assert_firebase_target' bash "$ROOT/scripts/android_dev_distribute.sh"; then
    echo "android_dev_distribute self-check: allowed defaults must pass" >&2
    rc=1
  fi

  if [[ $rc -ne 0 ]]; then
    exit 1
  fi
  echo "android_dev_distribute self-check: OK"
}

android_dev_distribute_main() {
  cd "$ROOT"

  local dry_run=1
  local yes=0
  local -a firebase_extra=()

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
      -h|--help)
        cat <<EOF
Usage: bash scripts/android_dev_distribute.sh [options] [-- extra firebase args]

Builds dev release APK. App Distribution upload is dry-run by default.

Options:
  --dry-run       Print upload plan only (default)
  --no-dry-run    Allow upload when combined with --yes
  --yes           Confirm Firebase App Distribution upload (--no-dry-run required)
  --self-check    Run refusal guard tests and exit
  -h, --help      Show this help

Allowed Firebase targets only:
  project: ${ALLOWED_PROJECT}
  app:     ${ALLOWED_APP_ID}
EOF
        exit 0
        ;;
      --)
        shift
        firebase_extra=("$@")
        break
        ;;
      -*)
        echo "android_dev_distribute: unknown option: $1" >&2
        exit 1
        ;;
      *)
        firebase_extra+=("$1")
        shift
        ;;
    esac
  done

  local project="${FIREBASE_ANDROID_DEV_PROJECT:-$ALLOWED_PROJECT}"
  local app_id="${FIREBASE_ANDROID_DEV_APP_ID:-$ALLOWED_APP_ID}"
  android_dev_distribute_assert_firebase_target "${firebase_extra[@]}"

  local apk="build/app/outputs/flutter-apk/app-dev-release.apk"
  local git_sha
  git_sha="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
  local release_notes="${RELEASE_NOTES:-Android dev $(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo manual)}"

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

  [[ -f "$apk" ]] || { echo "android_dev_distribute: missing $apk" >&2; exit 1; }

  local upload_cmd=(
    firebase appdistribution:distribute "$apk"
    --app "$app_id"
    --project "$project"
    --release-notes "$release_notes"
  )
  if [[ ${#firebase_extra[@]} -gt 0 ]]; then
    upload_cmd+=("${firebase_extra[@]}")
  fi

  if [[ "$dry_run" -eq 1 ]]; then
    echo "android_dev_distribute: dry-run (default): would run:"
    printf '  %q\n' "${upload_cmd[@]}"
    echo "android_dev_distribute: pass --no-dry-run --yes to upload"
    exit 0
  fi

  if [[ "$yes" -ne 1 ]]; then
    echo "android_dev_distribute: refused upload without --yes" >&2
    exit 1
  fi

  echo "android_dev_distribute: uploading to App Distribution (project=$project app=$app_id)"
  "${upload_cmd[@]}"

  echo "android_dev_distribute: done"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  android_dev_distribute_main "$@"
fi