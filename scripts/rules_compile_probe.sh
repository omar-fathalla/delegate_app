#!/usr/bin/env bash
# TAS-339: how long Google takes to compile a rules file (read-only).
#
# The Firebase Rules API refuses a ruleset whose compile takes more than
# about 6 s with `503 UNAVAILABLE` (on :test, rulesets.create and the release
# update alike), so a deploy fails even though the file is valid. This posts
# the file to projects/<project>:test, which only compiles it and changes
# nothing, and prints the HTTP code and the time of each run.
#
# Usage: bash scripts/rules_compile_probe.sh [rules file] [runs] [project]
#   defaults: firestore.rules, 5 runs, tashil-dev
# Needs `gcloud auth login` (an account that can read the project's rules).
# Times vary a lot from run to run on Google's side: compare several runs,
# and run a tiny ruleset next to it to see the current base time.
set -euo pipefail

FILE="${1:-firestore.rules}"
RUNS="${2:-5}"
PROJECT="${3:-tashil-dev}"

TOKEN="$(gcloud auth print-access-token)"
BODY="$(mktemp)"
OUT="$(mktemp)"
trap 'rm -f "$BODY" "$OUT"' EXIT

node -e '
const fs = require("fs");
const content = fs.readFileSync(process.argv[1], "utf8");
const name = /service\s+firebase\.storage/.test(content) ? "storage.rules" : "firestore.rules";
process.stdout.write(JSON.stringify({source: {files: [{name, content}]}}));
' "$FILE" > "$BODY"

echo "file: $FILE ($(wc -c < "$FILE" | tr -d ' ') bytes), project: $PROJECT"
for i in $(seq 1 "$RUNS"); do
  r="$(curl -s -o "$OUT" -w '%{http_code} %{time_total}' -X POST \
    "https://firebaserules.googleapis.com/v1/projects/${PROJECT}:test" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "x-goog-user-project: ${PROJECT}" \
    -H 'Content-Type: application/json' \
    --data-binary @"$BODY")"
  errors=""
  if [[ "${r%% *}" == "200" ]]; then
    errors="$(node -e '
const d = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
const n = (d.issues || []).filter((i) => i.severity === "ERROR").length;
process.stdout.write(n ? `${n} compile errors` : "ok");
' "$OUT")"
  fi
  echo "run $i: http ${r%% *}, ${r##* } s ${errors}"
done
