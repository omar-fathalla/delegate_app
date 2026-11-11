#!/usr/bin/env python3
"""Compare Firestore index coverage against queries used in this repo.

Default: check firestore.indexes.json against the required catalog (duplicate
checks and the org-admin renewal list). With --live --project <id>, also
compare that catalog to the project's *existing* indexes (list only).

Never use this to create or modify indexes. Prod
(practice-firebase-72df1) is refused.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import Iterable

PROD_PROJECT = "practice-firebase-72df1"

# queryScope, collectionGroup, fields (equality fields, no __name__)
# field overrides are encoded as ("FIELD", collection, field, scope, order)
REQUIRED = [
    {
        "id": "delegates.phoneNumber COLLECTION ASC",
        "kind": "field",
        "collectionGroup": "delegates",
        "fieldPath": "phoneNumber",
        "queryScope": "COLLECTION",
        "order": "ASCENDING",
        "why": "lookupDuplicateChains queries organizations/{org}/companies/{co}/delegates where phoneNumber ==",
    },
    {
        "id": "delegates.phoneNumber COLLECTION DESC",
        "kind": "field",
        "collectionGroup": "delegates",
        "fieldPath": "phoneNumber",
        "queryScope": "COLLECTION",
        "order": "DESCENDING",
        "why": "symmetric pair for the collection-scope phone override",
    },
    {
        "id": "delegates.phoneNumber COLLECTION_GROUP ASC",
        "kind": "field",
        "collectionGroup": "delegates",
        "fieldPath": "phoneNumber",
        "queryScope": "COLLECTION_GROUP",
        "order": "ASCENDING",
        "why": "collectionGroup('delegates').where('phoneNumber') (registration fallback / check_delegate_duplicate)",
    },
    {
        "id": "delegates.nationalId COLLECTION ASC",
        "kind": "field",
        "collectionGroup": "delegates",
        "fieldPath": "nationalId",
        "queryScope": "COLLECTION",
        "order": "ASCENDING",
        "why": "lookupDuplicateChains collection-scope nationalId query",
    },
    {
        "id": "delegates.nationalityID COLLECTION ASC",
        "kind": "field",
        "collectionGroup": "delegates",
        "fieldPath": "nationalityID",
        "queryScope": "COLLECTION",
        "order": "ASCENDING",
        "why": "lookupDuplicateChains collection-scope nationalityID query",
    },
    {
        "id": "delegate_requests companyUID+nationalId+status",
        "kind": "composite",
        "collectionGroup": "delegate_requests",
        "queryScope": "COLLECTION",
        "fields": ["companyUID", "nationalId", "status"],
        "why": "lookupDuplicateChains pending-request scan by nationalId",
    },
    {
        "id": "delegate_requests companyUID+phoneNumber+status",
        "kind": "composite",
        "collectionGroup": "delegate_requests",
        "queryScope": "COLLECTION",
        "fields": ["companyUID", "phoneNumber", "status"],
        "why": "lookupDuplicateChains pending-request scan by phoneNumber",
    },
    {
        "id": "delegate_requests organizationUID+companyUID+requestType+status",
        "kind": "composite",
        "collectionGroup": "delegate_requests",
        "queryScope": "COLLECTION",
        "fields": ["organizationUID", "companyUID", "requestType", "status"],
        "why": "org-admin renewal list and pending-renewals queries (need organizationUID)",
    },
    {
        "id": "delegate_requests companyUID+requestType+status",
        "kind": "composite",
        "collectionGroup": "delegate_requests",
        "queryScope": "COLLECTION",
        "fields": ["companyUID", "requestType", "status"],
        "why": "HR / company-admin renewal list (no organizationUID filter)",
    },
]


def repo_root() -> Path:
    here = Path(__file__).resolve()
    return here.parents[1]


def load_declared(path: Path) -> dict:
    return json.loads(path.read_text())


def declared_fields(doc: dict) -> set[tuple[str, str, str, str]]:
    """(collectionGroup, fieldPath, queryScope, order|CONTAINS)"""
    out = set()
    for fo in doc.get("fieldOverrides") or []:
        col = fo.get("collectionGroup")
        field = fo.get("fieldPath")
        for idx in fo.get("indexes") or []:
            if idx.get("arrayConfig"):
                order = "CONTAINS"
            else:
                order = idx.get("order") or ""
            scope = idx.get("queryScope") or ""
            out.add((col, field, scope, order))
    return out


def declared_composites(doc: dict) -> list[tuple[str, str, list[str]]]:
    out = []
    for idx in doc.get("indexes") or []:
        fields = [f.get("fieldPath") for f in idx.get("fields") or [] if f.get("fieldPath") and f.get("fieldPath") != "__name__"]
        out.append((idx.get("collectionGroup") or "", idx.get("queryScope") or "", fields))
    return out


def composite_covers(have: Iterable[tuple[str, str, list[str]]], col: str, scope: str, fields: list[str]) -> bool:
    need = set(fields)
    for hcol, hscope, hfields in have:
        if hcol != col or hscope != scope:
            continue
        # Equality-only queries are served by a composite whose field set
        # is exactly the queried fields (order may differ).
        if set(hfields) == need:
            return True
    return False


def gcloud_bin() -> str:
    for cand in (
        "/Users/fathalla/google-cloud-sdk/bin/gcloud",
        "gcloud",
    ):
        path = Path(cand) if cand.startswith("/") else None
        if path and path.exists():
            return str(path)
        if cand == "gcloud":
            return cand
    return "gcloud"


def run_gcloud(args: list[str]) -> list:
    cmd = ["env", "-u", "CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT", gcloud_bin(), *args]
    proc = subprocess.run(cmd, check=True, capture_output=True, text=True)
    data = json.loads(proc.stdout or "[]")
    return data if isinstance(data, list) else []


def live_fields(project: str) -> set[tuple[str, str, str, str]]:
    rows = run_gcloud(["firestore", "indexes", "fields", "list", f"--project={project}", "--format=json"])
    out = set()
    for row in rows:
        name = row.get("name") or ""
        # .../collectionGroups/{col}/fields/{field}
        col = field = ""
        if "collectionGroups/" in name:
            rest = name.split("collectionGroups/", 1)[1]
            parts = rest.split("/")
            col = parts[0] if parts else ""
            if "fields/" in rest:
                field = rest.split("fields/", 1)[1]
        indexes = (row.get("indexConfig") or {}).get("indexes") or []
        for idx in indexes:
            scope = idx.get("queryScope") or ""
            fields = idx.get("fields") or []
            # Single-field config: one field in fields[]
            for f in fields or [{}]:
                order = f.get("order") or ("CONTAINS" if f.get("arrayConfig") else "")
                fpath = f.get("fieldPath") or field
                out.add((col, fpath, scope, order))
    return out


def live_composites(project: str) -> list[tuple[str, str, list[str]]]:
    rows = run_gcloud(["firestore", "indexes", "composite", "list", f"--project={project}", "--format=json"])
    out = []
    for idx in rows:
        name = idx.get("name") or ""
        col = name.split("collectionGroups/")[1].split("/")[0] if "collectionGroups/" in name else ""
        fields = [f.get("fieldPath") for f in idx.get("fields") or [] if f.get("fieldPath") and f.get("fieldPath") != "__name__"]
        out.append((col, idx.get("queryScope") or "", fields, idx.get("state") or ""))
    # normalize to 3-tuple for covers(); keep state separately via ready set
    ready = []
    building = []
    for col, scope, fields, state in out:
        item = (col, scope, fields)
        if state == "READY":
            ready.append(item)
        else:
            building.append((item, state))
    return ready, building


def check(required, fields, composites, label: str, building=None) -> list[str]:
    missing = []
    for req in required:
        if req["kind"] == "field":
            key = (req["collectionGroup"], req["fieldPath"], req["queryScope"], req["order"])
            if key not in fields:
                missing.append(f"[{label}] missing field index: {req['id']} ({req['why']})")
        else:
            if not composite_covers(composites, req["collectionGroup"], req["queryScope"], req["fields"]):
                extra = ""
                if building:
                    for (item, state) in building:
                        if item[0] == req["collectionGroup"] and item[1] == req["queryScope"] and set(item[2]) == set(req["fields"]):
                            extra = f" (live state={state})"
                            break
                missing.append(f"[{label}] missing composite: {req['id']}{extra} ({req['why']})")
    return missing


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--indexes", default=str(repo_root() / "firestore.indexes.json"))
    parser.add_argument("--live", action="store_true", help="also list live indexes (read-only)")
    parser.add_argument("--project", help="GCP project for --live (tashil-dev). Prod is refused.")
    args = parser.parse_args()

    index_path = Path(args.indexes)
    if not index_path.is_file():
        print(f"indexes file not found: {index_path}", file=sys.stderr)
        return 2

    declared = load_declared(index_path)
    file_fields = declared_fields(declared)
    file_composites = declared_composites(declared)
    missing = check(REQUIRED, file_fields, file_composites, "firestore.indexes.json")

    if args.live:
        project = (args.project or "").strip()
        if not project:
            print("--live requires --project", file=sys.stderr)
            return 2
        if project == PROD_PROJECT:
            print(f"refusing to query prod project {PROD_PROJECT}", file=sys.stderr)
            return 2
        live_f = live_fields(project)
        live_c, building = live_composites(project)
        missing.extend(check(REQUIRED, live_f, live_c, f"live:{project}", building=building))

    if missing:
        print(f"{len(missing)} missing index(es):")
        for row in missing:
            print(f"  - {row}")
        return 1
    scope = "file"
    if args.live:
        scope = f"file + live:{args.project}"
    print(f"ok: all {len(REQUIRED)} required indexes are present ({scope}).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
