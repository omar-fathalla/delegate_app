#!/bin/sh
# Patrol `xcodebuild build-for-testing` + `generic/platform=iOS Simulator` often
# leaves ARCHS at "arm64 x86_64" with ONLY_ACTIVE_ARCH=NO. Flutter
# `debug_unpack_ios` must verify a single engine slice (arm64 on Apple Silicon
# sim, x86_64 on Intel). arm64e is never a valid unpack arch.
set -eu

command_name="${1:?usage: run_flutter_xcode_backend.sh <prepare|build|embed_and_thin>}"
shift

is_simulator=0
case "${SDKROOT:-}" in
  *[Ss]imulator*) is_simulator=1 ;;
esac
case "${PLATFORM_NAME:-}" in
  iphonesimulator) is_simulator=1 ;;
esac
if [ "${EFFECTIVE_PLATFORM_NAME:-}" = "-iphonesimulator" ]; then
  is_simulator=1
fi

archs="${ARCHS:-}"

if [ "$is_simulator" = 1 ]; then
  case "$(uname -m)" in
    arm64) archs=arm64 ;;
    x86_64) archs=x86_64 ;;
    *)
      if echo "$archs" | grep -qw arm64; then
        archs=arm64
      elif echo "$archs" | grep -qw x86_64; then
        archs=x86_64
      fi
      ;;
  esac
elif [ "$archs" = "arm64e" ]; then
  archs=arm64
elif [ -n "$archs" ] && echo "$archs" | grep -q ' ' && [ "${ONLY_ACTIVE_ARCH:-}" = "YES" ]; then
  native_arch="${NATIVE_ARCH:-${NATIVE_ARCH_ACTUAL:-}}"
  if echo "$native_arch" | grep -qE 'arm64e?|arm64' && echo "$archs" | grep -qw arm64; then
    archs=arm64
  elif echo "$native_arch" | grep -q x86_64 && echo "$archs" | grep -qw x86_64; then
    archs=x86_64
  fi
fi

export ARCHS="$archs"
if [ "$is_simulator" = 1 ]; then
  export ONLY_ACTIVE_ARCH=YES
fi

exec /bin/sh "$FLUTTER_ROOT/packages/flutter_tools/bin/xcode_backend.sh" "$command_name" "$@"
