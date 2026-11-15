#!/usr/bin/env bash
# Build dev-flavor release APK and upload to Firebase App Distribution (tashil-dev).
# No secrets in repo: uses local firebase login + optional env overrides.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_ID="${FIREBASE_ANDROID_DEV_APP_ID:-1:582609039627:android:40c38c45d1bdb99add720e}"
PROJECT="${FIREBASE_ANDROID_DEV_PROJECT:-tashil-dev}"
APK="build/app/outputs/flutter-apk/app-dev-release.apk"
RELEASE_NOTES="${RELEASE_NOTES:-Android dev $(git rev-parse --short HEAD 2>/dev/null || echo manual)}"

if ! command -v firebase >/dev/null 2>&1; then
  echo "android_dev_distribute: install Firebase CLI (https://firebase.google.com/docs/cli)" >&2
  exit 1
fi

echo "android_dev_distribute: flutter pub get"
flutter pub get --enforce-lockfile

echo "android_dev_distribute: building release dev APK"
flutter build apk --release --flavor dev --dart-define=ENV=dev

[[ -f "$APK" ]] || { echo "android_dev_distribute: missing $APK" >&2; exit 1; }

echo "android_dev_distribute: uploading to App Distribution (project=$PROJECT app=$APP_ID)"
firebase appdistribution:distribute "$APK" \
  --app "$APP_ID" \
  --project "$PROJECT" \
  --release-notes "$RELEASE_NOTES" \
  "$@"

echo "android_dev_distribute: done"