#!/bin/sh
# Strip Crashlytics from *-dev CocoaPods embed/link metadata only (prod *-prod untouched).
set -eu

IOS_ROOT="${1:-$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)}"
SUPPORT="${IOS_ROOT}/Pods/Target Support Files/Pods-Runner"
if [ ! -d "$SUPPORT" ]; then
  echo "[Tashil Pods] OK: no Pods-Runner support dir; skip Crashlytics pod strip."
  exit 0
fi

sanitize_xcconfig() {
  python3 - "$1" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
lines = text.splitlines()
out_lines: list[str] = []

crash_re = re.compile(r"crashlytics", re.IGNORECASE)

def sh_tokenize(s: str) -> list[str]:
    tokens: list[str] = []
    i = 0
    n = len(s)
    while i < n:
        if s[i].isspace():
            i += 1
            continue
        if s[i] in '"\'':
            q = s[i]
            j = i + 1
            while j < n and s[j] != q:
                if s[j] == "\\":
                    j += 2
                    continue
                j += 1
            tokens.append(s[i : j + 1])
            i = j + 1
            continue
        j = i
        while j < n and not s[j].isspace():
            j += 1
        tokens.append(s[i:j])
        i = j
    return tokens

def join_tokens(tokens: list[str]) -> str:
    return " ".join(tokens)

def strip_crashlytics_tokens(tokens: list[str]) -> list[str]:
    out: list[str] = []
    i = 0
    while i < len(tokens):
        tok = tokens[i]
        low = tok.lower().strip('"\'')
        if tok in ("-framework", "-weak_framework") and i + 1 < len(tokens):
            name = tokens[i + 1]
            if crash_re.search(name):
                i += 2
                continue
            out.extend([tok, name])
            i += 2
            continue
        if crash_re.search(tok):
            i += 1
            continue
        out.append(tok)
        i += 1
    return out

def collapse_orphan_framework_flags(tokens: list[str]) -> list[str]:
    out: list[str] = []
    i = 0
    while i < len(tokens):
        if tokens[i] == "-framework":
            if i + 1 < len(tokens) and not tokens[i + 1].startswith("-"):
                out.extend([tokens[i], tokens[i + 1]])
                i += 2
                continue
            i += 1
            continue
        out.append(tokens[i])
        i += 1
    return out

for line in lines:
    key, sep, rhs = line.partition("=")
    if not sep:
        if crash_re.search(line):
            continue
        out_lines.append(line)
        continue
    key_st = key.strip()
    if not crash_re.search(line) and "LDFLAGS" not in key_st:
        out_lines.append(line)
        continue
    tokens = sh_tokenize(rhs.strip())
    if crash_re.search(line):
        tokens = strip_crashlytics_tokens(tokens)
    if "LDFLAGS" in key_st:
        tokens = collapse_orphan_framework_flags(tokens)
    if not tokens:
        continue
    out_lines.append(f"{key_st} = {join_tokens(tokens)}")

path.write_text("\n".join(out_lines) + ("\n" if out_lines else ""), encoding="utf-8")
PY
}

for cfg in debug-dev profile-dev release-dev; do
  xcconfig="${SUPPORT}/Pods-Runner.${cfg}.xcconfig"
  if [ -f "$xcconfig" ]; then
    sanitize_xcconfig "$xcconfig"
    echo "[Tashil Pods] OK: stripped Crashlytics from Pods-Runner.${cfg}.xcconfig"
  fi
  for kind in input-files output-files; do
    list="${SUPPORT}/Pods-Runner-frameworks-${cfg}-${kind}.xcfilelist"
    if [ -f "$list" ]; then
      grep -vi 'crashlytics' "$list" >"${list}.tmp" || true
      mv "${list}.tmp" "$list"
      echo "[Tashil Pods] OK: stripped Crashlytics from $(basename "$list")"
    fi
  done
done

# Do not rewrite Pods-Runner-frameworks.sh wholesale — filelists + xcconfig are enough.
