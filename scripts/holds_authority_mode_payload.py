#!/usr/bin/env python3
"""PATCH body for a HOLDS_AUTHORITY_MODE flip/rollback.

Cloud Functions v1 replaces the whole environmentVariables map when the
updateMask is 'environmentVariables'. Dropping reserved keys such as
GCLOUD_PROJECT then removes them, and a v1 Firestore trigger does NOT
re-inject GCLOUD_PROJECT at runtime (that was the 19:30 Cairo outage).

A nested mask (environmentVariables.HOLDS_AUTHORITY_MODE) updates only
that key and leaves GCLOUD_PROJECT and every other existing variable
untouched. The reserved key is never sent in the body (sending it is HTTP 400).
"""
from __future__ import annotations

import json
import sys

ALLOWED_MODES = {"authoritative", "shadow"}
UPDATE_MASK = "environmentVariables.HOLDS_AUTHORITY_MODE"


def build_patch(mode: str) -> tuple[dict, str]:
    value = (mode or "").strip()
    if value not in ALLOWED_MODES:
        raise ValueError("mode must be authoritative or shadow")
    return {"environmentVariables": {"HOLDS_AUTHORITY_MODE": value}}, UPDATE_MASK


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: holds_authority_mode_payload.py <authoritative|shadow>", file=sys.stderr)
        return 2
    try:
        body, mask = build_patch(sys.argv[1])
    except ValueError as e:
        print(str(e), file=sys.stderr)
        return 2
    # One JSON object so the shell can split body vs mask without extra files.
    json.dump({"body": body, "updateMask": mask}, sys.stdout)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
