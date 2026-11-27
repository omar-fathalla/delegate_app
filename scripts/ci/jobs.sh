#!/usr/bin/env bash
# Single source of truth for CI job commands.
#
# Used by:
#   - .github/workflows/ci.yml   (each step: bash scripts/ci/run_job.sh <job>)
#   - scripts/local_ci.sh        (local mirror on the Mac)
#   - .claude/skills/pr-gate     (agents)
# Add or change a job HERE, never inline in ci.yml or local_ci.sh.
#
# Every job runs from the repo root of the checkout under test.
# bash 3.2 compatible (macOS stock bash): no declare -A, no mapfile.

# Jobs in default run order. android-dev-build is local-only (not in ci.yml).
CI_JOBS_ALL="analyze test emulator-ports p0-scripts build-web ios-guards android-guards functions rules android-dev-build"
CI_JOBS_GITHUB="analyze test emulator-ports p0-scripts build-web ios-guards android-guards functions rules"

# Device jobs: never part of a default run; asked for by name (local_ci.sh
# --jobs mac-gate, scripts/ci/mac_agent.sh after each merge to dev, nightly).
CI_JOBS_DEVICE="mac-gate"

# Jobs that start Firebase emulators and therefore need a port slot.
CI_JOBS_EMULATOR="emulator-ports p0-scripts functions rules"

# Timeout in minutes per job (same as ci.yml timeout-minutes).
ci_job_timeout() {
  case "$1" in
    analyze) echo 20 ;;
    test) echo 30 ;;
    emulator-ports) echo 12 ;;
    p0-scripts) echo 15 ;;
    build-web) echo 30 ;;
    ios-guards | android-guards) echo 5 ;;
    functions) echo 15 ;;
    rules) echo 25 ;;
    android-dev-build) echo 30 ;;
    mac-gate) echo 90 ;;
    *) echo 0 ;;
  esac
}

ci_job_exists() {
  case " $CI_JOBS_ALL $CI_JOBS_DEVICE " in *" $1 "*) return 0 ;; esac
  return 1
}

ci_job_needs_emulator() {
  case " $CI_JOBS_EMULATOR " in *" $1 "*) return 0 ;; esac
  return 1
}

# Every `test:rules*` script in package.json, so a new rules suite can never
# again exist without running in CI (status-guards/hr-web/storage did).
ci_rules_scripts() {
  node -e '
    const s = require("./package.json").scripts || {};
    console.log(Object.keys(s).filter(k => /^test:rules(:|$)/.test(k)).join("\n"));
  '
}

ci_rules_e2e_scripts() {
  printf '%s\n' \
    test:e2e:subscriptions \
    test:e2e:delegate \
    test:e2e:supervisor-reupload \
    test:e2e:privileged-reupload \
    test:e2e:approve-docs
}

# --- job bodies --------------------------------------------------------------

job_analyze() {
  flutter pub get --enforce-lockfile
  # Fails only on errors; warnings/infos are reported but don't fail the job.
  flutter analyze --no-fatal-warnings --no-fatal-infos
}

job_test() {
  flutter pub get --enforce-lockfile
  # Same as ci.yml (TAS-175: 4 files at a time; TAS-162: goldens run apart).
  flutter test --concurrency=4 --exclude-tags golden
}

job_emulator-ports() {
  npm install --no-audit --no-fund
  npm run test:scripts:emulator-slots
  npm run test:scripts:emulator-ports
}

job_p0-scripts() {
  (
    cd functions
    npm ci
    bash ../scripts/emulators_exec.sh --only auth,firestore --project demo-p0-scripts \
      "node --test scripts/p0-scripts.emulator.test.js"
  )
}

job_build-web() {
  flutter pub get --enforce-lockfile
  flutter build web --release
}

job_ios-guards() {
  bash scripts/ios_dev_config_check.sh
  bash scripts/maestro_check_flow_headers.sh
  bash scripts/patrol_check_integration_targets.sh
  bash patrol_test/manifest/test_xctestrun_resolve.sh
  bash scripts/holds_authority_mode_trap_test.sh
  python3 scripts/holds_authority_mode_payload_test.py
  bash test/scripts/ci_tooling_test.sh
}

job_android-guards() {
  bash scripts/android_dev_config_check.sh
  npm run test:scripts:android-dev-distribute-guard
}

job_functions() {
  (
    cd functions
    npm ci
    npm run lint
    npm test --if-present
  )
  npm install --no-audit --no-fund
  npm run test:e2e:staff
}

job_rules() {
  npm install --no-audit --no-fund
  npm --prefix functions ci
  local s
  for s in $(ci_rules_scripts) $(ci_rules_e2e_scripts); do
    echo "::group::npm run $s"
    npm run "$s"
    echo "::endgroup::"
  done
}

# Local only: AGENTS.md forbids building APKs unless asked, so local_ci.sh runs
# this only when the job list includes it explicitly or by default for a full run.
job_android-dev-build() {
  flutter pub get --enforce-lockfile
  flutter build apk --debug --flavor dev --dart-define=ENV=dev \
    --dart-define=GIT_SHA="${CI_SHA:-$(git rev-parse HEAD)}"
}

# Mac six-tool gate on one leased simulator (docs/testing/tool-roles.md,
# stages 4-6 + preflight). Steps can be narrowed for debugging:
#   CI_MAC_GATE_STEPS="ios-install preflight" bash scripts/ci/run_job.sh mac-gate
# Secrets: $CI_SECRETS_FILE (default ~/.tashil-ci.env, mode 600) with
#   PATROL_DEV_SECRET=...  TASHIL_MAESTRO_DEV_SECRET=...
# Artifacts (screenshot, Maestro logs): $CI_ARTIFACTS (default build/ci-results/mac-gate).
job_mac-gate() {
  local steps="${CI_MAC_GATE_STEPS:-ios-install preflight apk maestro patrol}"
  local art="${CI_ARTIFACTS:-$PWD/build/ci-results/mac-gate}"
  local secrets="${CI_SECRETS_FILE:-$HOME/.tashil-ci.env}"
  local sha
  sha="${CI_SHA:-$(git rev-parse HEAD)}"
  mkdir -p "$art"
  if [[ -f "$secrets" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$secrets"
    set +a
  fi
  case " $steps " in *" maestro "*)
    [[ -n "${TASHIL_MAESTRO_DEV_SECRET:-}" ]] || { echo "mac-gate: TASHIL_MAESTRO_DEV_SECRET missing (put it in $secrets)" >&2; return 1; } ;;
  esac
  case " $steps " in *" patrol "*)
    [[ -n "${PATROL_DEV_SECRET:-}" ]] || { echo "mac-gate: PATROL_DEV_SECRET missing (put it in $secrets)" >&2; return 1; } ;;
  esac
  (
    # shellcheck source=devices.sh
    source "$CI_DIR/devices.sh"
    # The device gate (Xcode build + simulator + Maestro/Patrol) is the heaviest
    # job; wait until no emulator job holds a port slot, up to CI_MAC_GATE_WAIT s.
    local waited=0 limit="${CI_MAC_GATE_WAIT:-1800}" d
    while :; do
      local busy=0
      for d in "$CI_LEASE_ROOT/slot"/*; do
        [[ -d "$d" ]] || continue
        _ci_lease_reap_if_stale "$d" || busy=1
      done
      (( busy )) || break
      if (( waited >= limit )); then
        echo "mac-gate: emulator jobs still running after ${limit}s, starting anyway" >&2
        break
      fi
      (( waited == 0 )) && echo "mac-gate: waiting for emulator CI jobs to finish ..." >&2
      sleep 30; waited=$(( waited + 30 ))
    done
    ci_ios_sim_acquire "mac-gate@${sha:0:8}"
    # Fake delegates bind to the first device that logs in (delegateLoginV2),
    # and every launch with a cleared keychain is a new device. Clear the
    # binding right before each device step so the simulator can log in.
    _reset_fake_delegates() {
      [[ -f functions/scripts/hr-web-fake-accounts.js ]] || return 0
      # Clean checkout: no functions/node_modules yet (firebase-admin).
      [[ -d functions/node_modules/firebase-admin ]] \
        || (cd functions && npm ci --no-audit --no-fund --silent) \
        || echo "mac-gate: warning: npm ci in functions failed" >&2
      (cd functions && GOOGLE_CLOUD_PROJECT=tashil-dev \
        node scripts/hr-web-fake-accounts.js --project tashil-dev --reset-device-bindings --apply) \
        || echo "mac-gate: warning: could not reset fake delegates' device bindings" >&2
    }
    # TAS-393: today's fake check-ins on Fake Branch Alpha, so the marketing
    # journeys have delegates to floor-check (fixed ids, idempotent per day).
    _seed_marketing_attendance() {
      [[ -f functions/scripts/seed-marketing-journey-attendance.js ]] || return 0
      (cd functions && GOOGLE_CLOUD_PROJECT=tashil-dev \
        node scripts/seed-marketing-journey-attendance.js --project tashil-dev --apply) \
        || echo "mac-gate: warning: could not seed the marketing journey attendance" >&2
    }
    trap ci_ios_sim_release EXIT
    local step
    for step in $steps; do
      echo "::group::mac-gate $step"
      case "$step" in
        ios-install)
          flutter pub get --enforce-lockfile
          flutter build ios --simulator --debug --flavor dev --dart-define=ENV=dev \
            --dart-define=GIT_SHA="$sha"
          xcrun simctl install "$CI_SIM_UDID" build/ios/iphonesimulator/Runner.app ;;
        preflight)
          TASHIL_PREFLIGHT_KEEP_BOOT=1 TASHIL_PROJECT_STORE="$art" TASHIL_PROJECT_STORE_MEDIA="$art" \
            bash scripts/mac_gate_preflight.sh ;;
        apk)
          flutter build apk --flavor dev --dart-define=ENV=dev --dart-define=GIT_SHA="$sha" ;;
        maestro)
          _reset_fake_delegates
          _seed_marketing_attendance
          TASHIL_CAPTURE_LOGIN_ROLES=0 TASHIL_MAESTRO_LOG_DIR="$art/maestro" \
            bash maestro/run-dev-user-journeys.sh ;;
        patrol)
          _reset_fake_delegates
          _seed_marketing_attendance
          bash scripts/patrol_run_dev_integration.sh -- -d "$CI_SIM_UDID" ;;
        *) echo "mac-gate: unknown step $step" >&2; exit 2 ;;
      esac
      echo "::endgroup::"
    done
  )
}

# --- change-based selection --------------------------------------------------

# Prints the jobs needed for a list of changed paths (stdin, one per line).
# Guards are always included: they are cheap and catch config drift.
ci_jobs_for_paths() {
  local want=" ios-guards android-guards " p
  add() {
    local j
    for j in "$@"; do
      case "$want" in *" $j "*) ;; *) want="$want$j " ;; esac
    done
  }
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    case "$p" in
      # Node-only tests under test/: no Flutter jobs for them.
      test/rules/* | test/e2e/*) add rules ;;
      test/scripts/*) add emulator-ports ;;
      .github/* | scripts/ci/* | scripts/local_ci.sh | package.json | package-lock.json)
        add $CI_JOBS_GITHUB ;;
      lib/* | test/* | pubspec.yaml | pubspec.lock | l10n.yaml | analysis_options.yaml | assets/*)
        add analyze test build-web ;;
      web/*) add build-web ;;
      functions/*) add functions p0-scripts rules ;;
      firestore.rules | firestore.deploy.rules | scripts/build_firestore_rules.js | storage.rules | firestore.indexes.json | firestore/* | firebase.json)
        add rules ;;
      scripts/emulator* | scripts/generate_emulator_firebase_config.js)
        add emulator-ports p0-scripts functions rules ;;
    esac
    case "$p" in
      test/rules/* | test/e2e/*) add rules ;;
      test/scripts/*) add emulator-ports ;;
    esac
  done
  # Keep CI_JOBS_ALL order.
  local j out=""
  for j in $CI_JOBS_ALL; do
    case "$want" in *" $j "*) out="$out $j" ;; esac
  done
  echo "${out# }"
}
