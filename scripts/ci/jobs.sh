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
    *) echo 0 ;;
  esac
}

ci_job_exists() {
  case " $CI_JOBS_ALL " in *" $1 "*) return 0 ;; esac
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
    test:e2e:privileged-reupload
}

# --- job bodies --------------------------------------------------------------

job_analyze() {
  flutter pub get --enforce-lockfile
  # Fails only on errors; warnings/infos are reported but don't fail the job.
  flutter analyze --no-fatal-warnings --no-fatal-infos
}

job_test() {
  flutter pub get --enforce-lockfile
  flutter test --concurrency=1
}

job_emulator-ports() {
  npm install --no-audit --no-fund
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
      .github/* | scripts/ci/* | scripts/local_ci.sh | package.json | package-lock.json)
        add $CI_JOBS_GITHUB ;;
      lib/* | test/* | pubspec.yaml | pubspec.lock | l10n.yaml | analysis_options.yaml | assets/*)
        add analyze test build-web ;;
      web/*) add build-web ;;
      functions/*) add functions p0-scripts rules ;;
      firestore.rules | storage.rules | firestore.indexes.json | firestore/* | firebase.json)
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
