#!/usr/bin/env bash
# Which Flutter SDK local CI uses for a commit (TAS-342).
#
# The version comes from the tested commit's own .fvmrc, so a CI script copy
# that is older or newer than the code can no longer run it with the wrong
# Flutter (25 Nov 2026: a stale checkout ran dev on 3.44.5 after the 3.50.1
# bump and every Flutter job failed in `pub get`).
#
#   source scripts/ci/flutter_sdk.sh
#   flutter_pinned_version <sha>     -> 3.50.1   (empty if no .fvmrc)
#   flutter_sdk_for_sha <sha>        -> $LOCAL_CI_FLUTTER_SDK if set,
#                                       else $LOCAL_CI_TOOLCHAINS/flutter-<version>
#                                       (default toolchains dir: ~/toolchains)
# bash 3.2 compatible.

flutter_pinned_version() {
  git show "$1:.fvmrc" 2>/dev/null \
    | sed -nE 's/.*"flutter"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' | head -n1
}

flutter_sdk_for_sha() {
  if [[ -n "${LOCAL_CI_FLUTTER_SDK:-}" ]]; then
    echo "$LOCAL_CI_FLUTTER_SDK"
    return 0
  fi
  local v
  v="$(flutter_pinned_version "$1")"
  if [[ -z "$v" ]]; then
    echo "local_ci: ERROR: no Flutter version in .fvmrc at ${1:0:8}; set LOCAL_CI_FLUTTER_SDK." >&2
    return 2
  fi
  echo "${LOCAL_CI_TOOLCHAINS:-$HOME/toolchains}/flutter-$v"
}
