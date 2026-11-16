#!/usr/bin/env bash
# Cursor Cloud Agent install for delegate_app.
#
# The heavy toolchain is installed only when the pinned version is missing.
# A Build snapshot keeps that disk, so later agents skip this script.
# A re-run on prepared disk refreshes lockfile installs only.
#
# Does not select a Firebase project.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

export FLUTTER_SUPPRESS_ANALYTICS=true
export GIT_TERMINAL_PROMPT=0
export DEBIAN_FRONTEND=noninteractive

log() {
  printf '==> %s\n' "$*"
}

phase_start() {
  PHASE_NAME="$1"
  PHASE_AT=$SECONDS
  log "$PHASE_NAME"
}

phase_end() {
  log "${PHASE_NAME} done in $((SECONDS - PHASE_AT))s"
}

read_flutter_version() {
  local version
  version="$(sed -n 's/.*"flutter"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' .fvmrc | head -1)"
  if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf 'Refusing to install Flutter: .fvmrc has no x.y.z pin (got %q)\n' "$version" >&2
    exit 1
  fi
  printf '%s\n' "$version"
}

read_firebase_tools_version() {
  local version
  version="$(sed -n 's/.*firebase-tools@\([0-9][0-9.]*\).*/\1/p' scripts/emulators_exec.sh | head -1)"
  if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf 'Refusing to cache emulators: scripts/emulators_exec.sh has no firebase-tools pin (got %q)\n' "$version" >&2
    exit 1
  fi
  printf '%s\n' "$version"
}

ensure_packages() {
  local missing=()
  command -v curl >/dev/null 2>&1 || missing+=(curl ca-certificates)
  command -v git >/dev/null 2>&1 || missing+=(git)
  command -v unzip >/dev/null 2>&1 || missing+=(unzip)
  command -v xz >/dev/null 2>&1 || missing+=(xz-utils)
  if ! java -version 2>&1 | grep -q 'version "21'; then
    missing+=(openjdk-21-jre-headless)
  fi
  if [[ ${#missing[@]} -eq 0 ]]; then
    log "system packages already present (curl, git, unzip, xz, Java 21)"
    return
  fi
  log "installing packages: ${missing[*]}"
  sudo apt-get update
  sudo apt-get install -y --no-install-recommends "${missing[@]}"
}

ensure_node() {
  # functions/package.json engines.node, firebase.json runtime, and CI are Node 22.
  # Patch 22.23.4 is installed only when no Node 22 is already on PATH.
  local node_version="22.23.4"
  if command -v node >/dev/null 2>&1; then
    local major
    major="$(node -p 'process.versions.node.split(".")[0]')"
    if [[ "$major" == "22" ]]; then
      log "Node $(node -v) already on PATH"
      return
    fi
  fi
  log "installing Node ${node_version}"
  local tmp
  tmp="$(mktemp -d)"
  curl -fL --retry 5 --retry-all-errors --retry-delay 2 \
    -o "$tmp/node.tar.xz" \
    "https://nodejs.org/dist/v${node_version}/node-v${node_version}-linux-x64.tar.xz"
  sudo tar -xJf "$tmp/node.tar.xz" -C /usr/local --strip-components=1
  rm -rf "$tmp"
  hash -r
  log "Node $(node -v) installed"
}

ensure_flutter() {
  local version="$1"
  local stamp="/opt/flutter/.tashil-sdk-version"
  local installed=""
  if [[ -x /opt/flutter/bin/flutter && -f "$stamp" ]]; then
    installed="$(tr -d '[:space:]' < "$stamp")"
  fi
  if [[ "$installed" == "$version" ]]; then
    log "Flutter ${version} already installed"
  else
    log "installing Flutter ${version} (found: ${installed:-none})"
    local tmp extract
    tmp="$(mktemp -d)"
    extract="$(mktemp -d)"
    curl -fL --retry 5 --retry-all-errors --retry-delay 2 \
      -o "$tmp/flutter.tar.xz" \
      "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${version}-stable.tar.xz"
    tar -xJf "$tmp/flutter.tar.xz" -C "$extract"
    if [[ ! -x "$extract/flutter/bin/flutter" ]]; then
      printf 'Flutter archive did not contain bin/flutter\n' >&2
      exit 1
    fi
    sudo rm -rf /opt/flutter
    sudo mv "$extract/flutter" /opt/flutter
    sudo chown -R "$(id -u):$(id -g)" /opt/flutter
    rm -rf "$tmp" "$extract"
    if ! git config --global --get-all safe.directory 2>/dev/null | grep -Fxq /opt/flutter; then
      git config --global --add safe.directory /opt/flutter
    fi
    log "enabling web and precaching web artifacts"
    CI=true /opt/flutter/bin/flutter config --no-analytics --enable-web
    CI=true /opt/flutter/bin/flutter precache --web
    printf '%s\n' "$version" > "$stamp"
  fi
  sudo ln -sfn /opt/flutter/bin/flutter /usr/local/bin/flutter
  sudo ln -sfn /opt/flutter/bin/dart /usr/local/bin/dart
  hash -r
  if [[ ! -d /opt/flutter/bin/cache/flutter_web_sdk ]]; then
    log "precaching Flutter web artifacts"
    CI=true flutter precache --web
  fi
  # Settings live under the home directory, which the snapshot keeps.
  CI=true flutter config --no-analytics --enable-web >/dev/null
}

cache_emulators() {
  local tools_version="$1"
  local cache_dir="${FIREBASE_EMULATORS_PATH:-$HOME/.cache/firebase/emulators}"
  local stamp="${cache_dir}/.tashil-firebase-tools-${tools_version}"
  local firestore=()
  local storage=()
  mkdir -p "$cache_dir"
  shopt -s nullglob
  firestore=("${cache_dir}"/cloud-firestore-emulator-*.jar)
  storage=("${cache_dir}"/cloud-storage-rules-runtime-*.jar)
  shopt -u nullglob
  if [[ -f "$stamp" && ${#firestore[@]} -gt 0 && ${#storage[@]} -gt 0 ]]; then
    log "Firebase emulator jars already cached for firebase-tools@${tools_version}"
    return
  fi
  log "downloading Firestore and Storage emulator jars (firebase-tools@${tools_version})"
  # setup:emulators:* only downloads jars. It does not select a project.
  npx --yes "firebase-tools@${tools_version}" setup:emulators:firestore
  npx --yes "firebase-tools@${tools_version}" setup:emulators:storage
  shopt -s nullglob
  firestore=("${cache_dir}"/cloud-firestore-emulator-*.jar)
  storage=("${cache_dir}"/cloud-storage-rules-runtime-*.jar)
  shopt -u nullglob
  if [[ ${#firestore[@]} -eq 0 || ${#storage[@]} -eq 0 ]]; then
    printf 'Emulator download finished without the expected jars in %s\n' "$cache_dir" >&2
    exit 1
  fi
  : > "$stamp"
}

pub_get_all() {
  local spec dir count=0
  local specs=()
  if [[ -f pubspec.yaml ]]; then
    specs+=(./pubspec.yaml)
  fi
  while IFS= read -r spec; do
    [[ "$spec" == "./pubspec.yaml" ]] && continue
    specs+=("$spec")
  done < <(find . -name pubspec.yaml \
    -not -path './.dart_tool/*' \
    -not -path './build/*' \
    -not -path './.fvm/*' \
    -not -path './ios/.symlinks/*' \
    -not -path './ios/Pods/*' \
    -not -path './.pub-cache/*' \
    | sort)
  if [[ ${#specs[@]} -eq 0 ]]; then
    printf 'No pubspec.yaml found\n' >&2
    exit 1
  fi
  for spec in "${specs[@]}"; do
    dir="$(dirname "$spec")"
    log "flutter pub get --enforce-lockfile in ${dir}"
    (cd "$dir" && flutter pub get --enforce-lockfile)
    count=$((count + 1))
  done
  log "pub get completed for ${count} package(s)"
  # pubspec `generate: true` rewrites committed lib/l10n from the arb files.
  # Put those tracked files back so install does not dirty the checkout.
  if [[ -d lib/l10n ]] && ! git diff --quiet -- lib/l10n; then
    log "restoring generated lib/l10n so the checkout stays clean"
    git checkout -- lib/l10n
  fi
}

npm_install_root() {
  if [[ ! -f package.json ]]; then
    log "no root package.json; skipping root npm install"
    return
  fi
  if [[ -f package-lock.json ]]; then
    log "npm ci (root lockfile present)"
    npm ci
    return
  fi
  # Root package-lock.json is gitignored, so a fresh checkout matches CI:
  # `npm install --no-audit --no-fund` in the rules job.
  log "npm install (root lockfile is not in the checkout)"
  npm install --no-audit --no-fund
}

npm_ci_functions() {
  if [[ ! -f functions/package-lock.json ]]; then
    printf 'functions/package-lock.json is missing; refusing npm ci\n' >&2
    exit 1
  fi
  log "npm ci in functions/"
  npm ci --prefix functions
}

FLUTTER_VERSION="$(read_flutter_version)"
FIREBASE_TOOLS_VERSION="$(read_firebase_tools_version)"
log "pins: flutter ${FLUTTER_VERSION}, firebase-tools ${FIREBASE_TOOLS_VERSION}, node 22"

phase_start "system packages"
ensure_packages
phase_end

phase_start "node"
ensure_node
phase_end

phase_start "flutter"
ensure_flutter "$FLUTTER_VERSION"
phase_end

phase_start "firebase emulators"
cache_emulators "$FIREBASE_TOOLS_VERSION"
phase_end

phase_start "flutter pub get"
pub_get_all
phase_end

phase_start "npm"
npm_install_root
npm_ci_functions
phase_end

log "cloud-agent install complete in ${SECONDS}s"
flutter --version
node -v
java -version
