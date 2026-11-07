#!/usr/bin/env python3
"""Plist helpers for ios/scripts (macOS + Linux CI; replaces PlistBuddy when absent)."""
from __future__ import annotations

import plistlib
import sys
from pathlib import Path
from typing import Any


def load_plist(path: Path) -> dict[str, Any]:
    with path.open("rb") as f:
        data = plistlib.load(f)
    if not isinstance(data, dict):
        raise SystemExit(f"expected dict root in {path}")
    return data


def cmd_get(path: Path, key: str) -> None:
    d = load_plist(path)
    v = d.get(key)
    if v is None:
        print("")
    elif isinstance(v, bool):
        print("true" if v else "false")
    else:
        print(v)


def cmd_patch_info(path: Path, app_env: str) -> None:
    d = load_plist(path)
    d["TashilEnv"] = app_env
    if app_env == "dev":
        d["FirebaseAutomaticDataCollectionEnabled"] = False
        d["FirebaseCrashlyticsCollectionEnabled"] = False
        d["FIREBASE_ANALYTICS_COLLECTION_ENABLED"] = False
        d["FIREBASE_ANALYTICS_COLLECTION_DEACTIVATED"] = True
        d["GOOGLE_ANALYTICS_ADID_COLLECTION_ENABLED"] = False
        d["GOOGLE_ANALYTICS_IDFV_COLLECTION_ENABLED"] = False
        d["GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_PERSONALIZATION_SIGNALS"] = False
    with path.open("wb") as f:
        plistlib.dump(d, f, fmt=plistlib.FMT_XML)


def main() -> None:
    if len(sys.argv) < 2:
        raise SystemExit("usage: tashil_plist_tools.py get <file> <key> | patch-info <file> <dev|prod>")

    sub = sys.argv[1]
    if sub == "get" and len(sys.argv) == 4:
        cmd_get(Path(sys.argv[2]), sys.argv[3])
        return
    if sub == "patch-info" and len(sys.argv) == 4:
        env = sys.argv[3]
        if env not in ("dev", "prod"):
            raise SystemExit("patch-info app_env must be dev or prod")
        cmd_patch_info(Path(sys.argv[2]), env)
        return
    raise SystemExit("usage: tashil_plist_tools.py get <file> <key> | patch-info <file> <dev|prod>")


if __name__ == "__main__":
    main()
