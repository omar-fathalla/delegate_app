#!/usr/bin/env python3
"""Resolve Patrol iOS integration paths from an .xctestrun plist (format 1 or 2)."""

from __future__ import annotations

import os
import plistlib
import sys
from typing import Any


def _resolve_template(
    template: str,
    testroot: str,
    testhost: str | None = None,
    platforms: str | None = None,
) -> str:
    path = template
    path = path.replace("__TESTROOT__", testroot)
    if testhost is not None:
        path = path.replace("__TESTHOST__", testhost)
    if platforms is not None:
        path = path.replace("__PLATFORMS__", platforms)
    return path


def _iter_test_targets(plist_data: dict[str, Any]) -> list[tuple[str, dict[str, Any]]]:
    metadata = plist_data.get("__xctestrun_metadata__") or {}
    format_version = metadata.get("FormatVersion", 1)
    if format_version >= 2 or "TestConfigurations" in plist_data:
        out: list[tuple[str, dict[str, Any]]] = []
        for cfg in plist_data.get("TestConfigurations") or []:
            for target in cfg.get("TestTargets") or []:
                name = str(target.get("BlueprintName") or target.get("TargetName") or "")
                out.append((name, target))
        return out

    targets: list[tuple[str, dict[str, Any]]] = []
    for key, val in plist_data.items():
        if key.startswith("__"):
            continue
        if isinstance(val, dict) and "TestBundlePath" in val:
            targets.append((key, val))
    return targets


def pick_ui_test_target(plist_data: dict[str, Any]) -> tuple[str, dict[str, Any]] | None:
    """Prefer a UI-test target (has UITargetAppPath), else first target with TestHostPath."""
    candidates = _iter_test_targets(plist_data)
    for name, target in candidates:
        if target.get("UITargetAppPath"):
            return name, target
    for name, target in candidates:
        if target.get("TestHostPath") and target.get("TestBundlePath"):
            return name, target
    return None


def resolve_paths(xctestrun_path: str) -> dict[str, str]:
    with open(xctestrun_path, "rb") as fh:
        plist_data = plistlib.load(fh)

    picked = pick_ui_test_target(plist_data)
    if not picked:
        raise SystemExit(f"error: no test target with TestBundlePath in {xctestrun_path}")

    blueprint_name, target = picked
    testroot = os.path.dirname(os.path.abspath(xctestrun_path))
    platforms = os.path.join(
        os.environ.get("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer"),
        "Platforms",
    )

    raw_host = target.get("TestHostPath") or ""
    raw_bundle = target.get("TestBundlePath") or ""
    raw_ui_target = target.get("UITargetAppPath") or ""

    if not raw_host or not raw_bundle:
        raise SystemExit(
            f"error: TestHostPath/TestBundlePath missing for target {blueprint_name!r}"
        )

    test_host = _resolve_template(str(raw_host), testroot, platforms=platforms)
    test_bundle = _resolve_template(
        str(raw_bundle), testroot, testhost=test_host, platforms=platforms
    )
    ui_target = ""
    if raw_ui_target:
        ui_target = _resolve_template(str(raw_ui_target), testroot, platforms=platforms)

    if not ui_target:
        raise SystemExit(
            f"error: UITargetAppPath missing for UI test target {blueprint_name!r}"
        )

    return {
        "blueprint_name": blueprint_name,
        "ui_target_app": os.path.normpath(ui_target),
        "test_runner_app": os.path.normpath(test_host),
        "test_bundle": os.path.normpath(test_bundle),
        "raw_test_host_path": str(raw_host),
        "raw_test_bundle_path": str(raw_bundle),
        "raw_ui_target_app_path": str(raw_ui_target),
        "xctestrun_format_version": str(
            (plist_data.get("__xctestrun_metadata__") or {}).get("FormatVersion", 1)
        ),
    }


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(f"usage: {sys.argv[0]} <path-to.xctestrun>")
    for key, value in resolve_paths(sys.argv[1]).items():
        print(f"{key}={value}")


if __name__ == "__main__":
    main()
