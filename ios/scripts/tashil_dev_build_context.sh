#!/bin/sh
# Shared dev-flavor detection for iOS strip / guard scripts (no secrets).
tashil_is_dev_build() {
  case "${CONFIGURATION:-}" in
    Debug-dev | Profile-dev | Release-dev) return 0 ;;
  esac
  case "${APP_ENV:-}" in
    dev) return 0 ;;
  esac
  case "${PRODUCT_BUNDLE_IDENTIFIER:-}" in
    *delegate.dev) return 0 ;;
  esac
  if [ -n "${DART_DEFINES:-}" ]; then
    old_ifs=$IFS
    IFS=,
    for encoded in $DART_DEFINES; do
      decoded=$(printf '%s' "$encoded" | base64 -d 2>/dev/null || true)
      if [ "$decoded" = "ENV=dev" ]; then
        IFS=$old_ifs
        return 0
      fi
    done
    IFS=$old_ifs
  fi
  return 1
}
