#!/usr/bin/env python3
"""Compare firestore.indexes.json with live prod indexes (read-only).

Fetches composite indexes and custom field overrides from the Firestore
Admin API using GET only. Never creates, updates, or deletes anything.

Exit codes:
  0  File would not delete any prod index or field override.
     Extra entries in the file (would be created on deploy) are listed.
  1  Deploying the file would DELETE at least one prod index or override.
  2  Usage, credentials, or request error.

Credentials (first match wins):
  FIREBASE_INDEX_READER_SA
      Service-account JSON content, or a path to a JSON file.
      This is the repo secret used by the GitHub Actions workflow.
  GOOGLE_APPLICATION_CREDENTIALS
      Path to a service-account JSON file.
  FIREBASE_SERVICE_ACCOUNT_JSON
      PEM private key only. Also set FIREBASE_CLIENT_EMAIL and
      FIREBASE_PROJECT_ID (or pass --project).

This script never prints credential values.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.parse
from typing import Any

import requests
from google.auth.transport.requests import Request
from google.oauth2 import service_account

PROD_PROJECT = "practice-firebase-72df1"
DEFAULT_DATABASE = "(default)"
SCOPE = "https://www.googleapis.com/auth/cloud-platform"

# Firestore default single-field indexes (ancestor / __default__.*).
DEFAULT_FIELD_INDEXES = frozenset(
    [
        ("COLLECTION", "ASCENDING", None),
        ("COLLECTION", "DESCENDING", None),
        ("COLLECTION", None, "CONTAINS"),
    ]
)

DENSITY_DEFAULT = "SPARSE_ALL"

SCOPE_RANK = {"COLLECTION": 0, "COLLECTION_GROUP": 1}
KIND_RANK = {"ASCENDING": 0, "DESCENDING": 1, "CONTAINS": 2}


def repo_root() -> str:
    return os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


def default_indexes_path() -> str:
    return os.path.join(repo_root(), "firestore.indexes.json")


# ---------------------------------------------------------------------------
# Credentials (never logged)
# ---------------------------------------------------------------------------

def _sa_info_from_pem(pem_raw: str, project: str) -> dict[str, str]:
    email = (os.environ.get("FIREBASE_CLIENT_EMAIL") or "").strip()
    if not email:
        raise ValueError(
            "FIREBASE_SERVICE_ACCOUNT_JSON is a PEM key; set "
            "FIREBASE_CLIENT_EMAIL (and --project or FIREBASE_PROJECT_ID)."
        )
    return {
        "type": "service_account",
        "project_id": project,
        "private_key": pem_raw.replace("\\n", "\n"),
        "client_email": email,
        "token_uri": "https://oauth2.googleapis.com/token",
    }


def _load_sa_info(project: str) -> dict[str, Any]:
    raw = (os.environ.get("FIREBASE_INDEX_READER_SA") or "").strip()
    if raw:
        if raw.startswith("{"):
            return json.loads(raw)
        if os.path.isfile(raw):
            with open(raw, encoding="utf-8") as fh:
                return json.load(fh)
        raise ValueError(
            "FIREBASE_INDEX_READER_SA is set but is not JSON and is not a file path."
        )

    path = (os.environ.get("GOOGLE_APPLICATION_CREDENTIALS") or "").strip()
    if path:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)

    pem = os.environ.get("FIREBASE_SERVICE_ACCOUNT_JSON") or ""
    if pem.strip():
        return _sa_info_from_pem(pem, project)

    raise ValueError(
        "No credentials. Set repo secret FIREBASE_INDEX_READER_SA "
        "(service-account JSON with permission to list Firestore indexes), "
        "or GOOGLE_APPLICATION_CREDENTIALS, or FIREBASE_SERVICE_ACCOUNT_JSON."
    )


def _authorized_session(project: str) -> requests.Session:
    info = _load_sa_info(project)
    creds = service_account.Credentials.from_service_account_info(
        info, scopes=[SCOPE]
    )
    creds.refresh(Request())
    session = requests.Session()
    session.headers["Authorization"] = f"Bearer {creds.token}"
    return session


# ---------------------------------------------------------------------------
# Read-only Firestore Admin API
# ---------------------------------------------------------------------------

def _db_root(project: str, database: str) -> str:
    db = urllib.parse.quote(database, safe="")
    return (
        f"https://firestore.googleapis.com/v1/projects/{project}"
        f"/databases/{db}/collectionGroups/-"
    )


def _get_paginated(session: requests.Session, url: str, list_key: str, params: dict[str, str] | None = None) -> list:
    items: list = []
    query = dict(params or {})
    while True:
        response = session.get(url, params=query, timeout=60)
        if response.status_code != 200:
            message = ""
            try:
                err = response.json().get("error") or {}
                message = f" {err.get('status')}: {err.get('message')}"
            except Exception:
                message = f" body_len={len(response.content)}"
            raise RuntimeError(
                f"GET {url} failed with HTTP {response.status_code}.{message} "
                "(read-only list; no writes were attempted)."
            )
        payload = response.json()
        items.extend(payload.get(list_key) or [])
        token = payload.get("nextPageToken")
        if not token:
            break
        query["pageToken"] = token
    return items


def fetch_live(project: str, database: str) -> tuple[list, list]:
    session = _authorized_session(project)
    root = _db_root(project, database)
    composites = _get_paginated(session, f"{root}/indexes", "indexes")
    fields = _get_paginated(
        session,
        f"{root}/fields",
        "fields",
        {"filter": "indexConfig.usesAncestorConfig:false"},
    )
    return composites, fields


# ---------------------------------------------------------------------------
# Normalization
# ---------------------------------------------------------------------------

def _collection_group_from_name(name: str) -> str:
    parts = name.split("/")
    try:
        return urllib.parse.unquote(parts[parts.index("collectionGroups") + 1])
    except (ValueError, IndexError):
        return ""


def _field_path_from_name(name: str) -> str:
    parts = name.split("/")
    try:
        return urllib.parse.unquote(parts[parts.index("fields") + 1])
    except (ValueError, IndexError):
        return ""


def _strip_auto_name(fields: list[dict]) -> list[dict]:
    """Drop the trailing __name__ field Firestore always appends.

    Kept only when its order does not match the previous field, which would
    mean it was set explicitly and must stay in the file.
    """
    if not fields:
        return []
    last = fields[-1]
    if last.get("fieldPath") != "__name__":
        return list(fields)
    if len(fields) >= 2:
        prev = fields[-2]
        if prev.get("order") and prev.get("order") != last.get("order"):
            return list(fields)
    return list(fields[:-1])


def _cli_field(field: dict) -> dict:
    out: dict[str, Any] = {"fieldPath": field["fieldPath"]}
    if field.get("order"):
        out["order"] = field["order"]
    if field.get("arrayConfig"):
        out["arrayConfig"] = field["arrayConfig"]
    if field.get("vectorConfig"):
        out["vectorConfig"] = field["vectorConfig"]
    return out


def _field_tuple(field: dict) -> tuple:
    vector = field.get("vectorConfig")
    return (
        field.get("fieldPath"),
        field.get("order"),
        field.get("arrayConfig"),
        json.dumps(vector, sort_keys=True) if vector else None,
    )


def live_composites_to_cli(live: list[dict]) -> list[dict]:
    out = []
    for item in live:
        fields = [_cli_field(f) for f in _strip_auto_name(item.get("fields") or [])]
        cli = {
            "collectionGroup": _collection_group_from_name(item.get("name") or ""),
            "queryScope": item.get("queryScope") or "COLLECTION",
            "fields": fields,
        }
        density = item.get("density") or DENSITY_DEFAULT
        if density:
            cli["density"] = density
        out.append(cli)
    return out


def _is_default_star(collection_group: str, field_path: str) -> bool:
    return collection_group == "__default__" or field_path in {"*", "%2A"}


def _cli_field_index(index: dict) -> dict:
    scope = index.get("queryScope") or "COLLECTION"
    fields = index.get("fields") or []
    if fields:
        head = fields[0]
        if head.get("order"):
            return {"order": head["order"], "queryScope": scope}
        if head.get("arrayConfig"):
            return {"arrayConfig": head["arrayConfig"], "queryScope": scope}
    if index.get("order"):
        return {"order": index["order"], "queryScope": scope}
    if index.get("arrayConfig"):
        return {"arrayConfig": index["arrayConfig"], "queryScope": scope}
    return {"queryScope": scope}


def live_fields_to_cli(live: list[dict]) -> list[dict]:
    out = []
    for item in live:
        cg = _collection_group_from_name(item.get("name") or "")
        field_path = _field_path_from_name(item.get("name") or "")
        if _is_default_star(cg, field_path):
            continue
        cfg = item.get("indexConfig") or {}
        indexes = [_cli_field_index(ix) for ix in (cfg.get("indexes") or [])]
        entry: dict[str, Any] = {
            "collectionGroup": cg,
            "fieldPath": field_path,
            "indexes": indexes,
        }
        ttl_cfg = item.get("ttlConfig")
        if ttl_cfg:
            # Present only when TTL is actually configured on prod.
            entry["ttl"] = True
        out.append(entry)
    return out


def _override_index_key(index: dict) -> tuple:
    return (
        index.get("queryScope") or "COLLECTION",
        index.get("order"),
        index.get("arrayConfig"),
    )


def _composite_key(index: dict) -> tuple:
    fields = tuple(_field_tuple(f) for f in _strip_auto_name(index.get("fields") or []))
    density = index.get("density") or DENSITY_DEFAULT
    return (
        index.get("collectionGroup") or "",
        index.get("queryScope") or "COLLECTION",
        fields,
        density,
    )


def _describe_composite(key: tuple) -> str:
    cg, scope, fields, density = key
    parts = []
    for path, order, array, _vector in fields:
        kind = order or array or "?"
        parts.append(f"{path}:{kind}")
    dens = f" density={density}" if density and density != DENSITY_DEFAULT else ""
    return f"{cg} {scope} [{', '.join(parts)}]{dens}"


def _describe_field_index(cg: str, field: str, key: tuple) -> str:
    scope, order, array = key
    kind = order or array or "?"
    return f"{cg}.{field} {scope} {kind}"


def file_override_map(doc: dict) -> dict[tuple[str, str], set[tuple]]:
    out: dict[tuple[str, str], set[tuple]] = {}
    for item in doc.get("fieldOverrides") or []:
        cg = item.get("collectionGroup") or ""
        field = item.get("fieldPath") or ""
        if _is_default_star(cg, field):
            continue
        out[(cg, field)] = {_override_index_key(ix) for ix in (item.get("indexes") or [])}
    return out


def live_override_map(cli_overrides: list[dict]) -> dict[tuple[str, str], set[tuple]]:
    out: dict[tuple[str, str], set[tuple]] = {}
    for item in cli_overrides:
        cg = item["collectionGroup"]
        field = item["fieldPath"]
        out[(cg, field)] = {_override_index_key(ix) for ix in item.get("indexes") or []}
    return out


def effective_field_indexes(overrides: dict[tuple[str, str], set[tuple]], key: tuple[str, str]) -> set[tuple]:
    if key in overrides:
        return set(overrides[key])
    return set(DEFAULT_FIELD_INDEXES)


# ---------------------------------------------------------------------------
# Diff (deploy of `file` against `prod`)
# ---------------------------------------------------------------------------

def diff_indexes(file_doc: dict, live_composites: list[dict], live_fields: list[dict]) -> dict[str, list[str]]:
    file_keys = {_composite_key(i) for i in (file_doc.get("indexes") or [])}
    prod_cli = live_composites_to_cli(live_composites)
    prod_keys = {_composite_key(i) for i in prod_cli}

    composite_deletes = sorted(prod_keys - file_keys, key=_describe_composite)
    composite_adds = sorted(file_keys - prod_keys, key=_describe_composite)

    file_ov = file_override_map(file_doc)
    prod_ov = live_override_map(live_fields_to_cli(live_fields))

    field_deletes: list[str] = []
    field_adds: list[str] = []
    all_fields = set(file_ov) | set(prod_ov)

    # Also catch a file override that would drop default indexes on a field
    # that still uses ancestor config on prod (not present in prod_ov).
    for key in all_fields:
        want = effective_field_indexes(file_ov, key)
        have = effective_field_indexes(prod_ov, key)
        cg, field = key
        for item in sorted(have - want):
            field_deletes.append(_describe_field_index(cg, field, item))
        for item in sorted(want - have):
            field_adds.append(_describe_field_index(cg, field, item))

        # Whole-override removal: file dropped a custom override and the
        # field would fall back to defaults. Already covered by the set
        # difference above, but mention the override itself when prod had
        # a custom config and the file has none.
        if key in prod_ov and key not in file_ov:
            # prepend a clearer line if any deletes already recorded
            pass

    return {
        "composite_deletes": [_describe_composite(k) for k in composite_deletes],
        "composite_adds": [_describe_composite(k) for k in composite_adds],
        "field_deletes": field_deletes,
        "field_adds": field_adds,
        "prod_composite_count": str(len(prod_keys)),
        "file_composite_count": str(len(file_keys)),
        "prod_override_count": str(len(prod_ov)),
        "file_override_count": str(len(file_ov)),
    }


# ---------------------------------------------------------------------------
# Stable export (local file only)
# ---------------------------------------------------------------------------

def _sort_key_composite(index: dict) -> tuple:
    fields = tuple(_field_tuple(f) for f in index.get("fields") or [])
    return (
        index.get("collectionGroup") or "",
        SCOPE_RANK.get(index.get("queryScope") or "", 99),
        fields,
    )


def _sort_key_field_index(index: dict) -> tuple:
    kind = index.get("order") or index.get("arrayConfig") or ""
    return (
        SCOPE_RANK.get(index.get("queryScope") or "", 99),
        KIND_RANK.get(kind, 99),
        kind,
    )


def build_cli_document(live_composites: list[dict], live_fields: list[dict]) -> dict:
    indexes = sorted(live_composites_to_cli(live_composites), key=_sort_key_composite)
    overrides = live_fields_to_cli(live_fields)
    for item in overrides:
        item["indexes"] = sorted(item.get("indexes") or [], key=_sort_key_field_index)
    overrides = sorted(
        overrides,
        key=lambda o: (o.get("collectionGroup") or "", o.get("fieldPath") or ""),
    )
    return {"indexes": indexes, "fieldOverrides": overrides}


def dump_cli_document(doc: dict) -> str:
    return json.dumps(doc, indent=2, ensure_ascii=True) + "\n"


# ---------------------------------------------------------------------------
# Self-test (no network)
# ---------------------------------------------------------------------------

def _self_test() -> int:
    failures: list[str] = []

    def check(name: str, cond: bool, detail: str = "") -> None:
        if not cond:
            failures.append(f"{name}: {detail}" if detail else name)

    live_composite = {
        "name": "projects/p/databases/(default)/collectionGroups/widgets/indexes/abc",
        "queryScope": "COLLECTION",
        "density": "SPARSE_ALL",
        "fields": [
            {"fieldPath": "status", "order": "ASCENDING"},
            {"fieldPath": "createdAt", "order": "DESCENDING"},
            {"fieldPath": "__name__", "order": "DESCENDING"},
        ],
    }
    live_field = {
        "name": "projects/p/databases/(default)/collectionGroups/widgets/fields/orgId",
        "indexConfig": {
            "indexes": [
                {
                    "queryScope": "COLLECTION",
                    "fields": [{"fieldPath": "orgId", "order": "ASCENDING"}],
                },
                {
                    "queryScope": "COLLECTION",
                    "fields": [{"fieldPath": "orgId", "order": "DESCENDING"}],
                },
                {
                    "queryScope": "COLLECTION",
                    "fields": [{"fieldPath": "orgId", "arrayConfig": "CONTAINS"}],
                },
                {
                    "queryScope": "COLLECTION_GROUP",
                    "fields": [{"fieldPath": "orgId", "order": "ASCENDING"}],
                },
            ]
        },
    }
    default_star = {
        "name": "projects/p/databases/(default)/collectionGroups/__default__/fields/*",
        "indexConfig": {
            "indexes": [
                {"queryScope": "COLLECTION", "fields": [{"fieldPath": "*", "order": "ASCENDING"}]},
            ]
        },
    }

    matched = build_cli_document([live_composite], [live_field, default_star])
    check("__default__ omitted", all(o["collectionGroup"] != "__default__" for o in matched["fieldOverrides"]))
    check("__name__ stripped", all(f["fieldPath"] != "__name__" for f in matched["indexes"][0]["fields"]))
    diff = diff_indexes(matched, [live_composite], [live_field, default_star])
    check(
        "identical is zero diff",
        not any(diff[k] for k in ("composite_deletes", "composite_adds", "field_deletes", "field_adds")),
        str(diff),
    )

    # Missing composite → delete
    empty = {"indexes": [], "fieldOverrides": matched["fieldOverrides"]}
    diff = diff_indexes(empty, [live_composite], [live_field, default_star])
    check("missing composite is delete", len(diff["composite_deletes"]) == 1, str(diff["composite_deletes"]))

    # Extra composite → add, not delete
    extra_idx = {
        "collectionGroup": "widgets",
        "queryScope": "COLLECTION",
        "fields": [{"fieldPath": "name", "order": "ASCENDING"}],
        "density": "SPARSE_ALL",
    }
    with_extra = {
        "indexes": matched["indexes"] + [extra_idx],
        "fieldOverrides": matched["fieldOverrides"],
    }
    diff = diff_indexes(with_extra, [live_composite], [live_field, default_star])
    check("extra composite is add", len(diff["composite_adds"]) == 1 and not diff["composite_deletes"], str(diff))

    # File override drops a prod collection-group index → delete
    dropped = {
        "indexes": matched["indexes"],
        "fieldOverrides": [
            {
                "collectionGroup": "widgets",
                "fieldPath": "orgId",
                "indexes": [
                    {"order": "ASCENDING", "queryScope": "COLLECTION"},
                    {"order": "DESCENDING", "queryScope": "COLLECTION"},
                    {"arrayConfig": "CONTAINS", "queryScope": "COLLECTION"},
                ],
            }
        ],
    }
    diff = diff_indexes(dropped, [live_composite], [live_field, default_star])
    check(
        "dropped CG field index is delete",
        any("COLLECTION_GROUP" in line and "orgId" in line for line in diff["field_deletes"]),
        str(diff["field_deletes"]),
    )

    # File override on a defaulted prod field that omits CONTAINS → delete
    ttl_override = {
        "indexes": matched["indexes"],
        "fieldOverrides": matched["fieldOverrides"]
        + [
            {
                "collectionGroup": "requests",
                "fieldPath": "ttlAt",
                "indexes": [
                    {"order": "ASCENDING", "queryScope": "COLLECTION"},
                    {"order": "DESCENDING", "queryScope": "COLLECTION"},
                    {"order": "ASCENDING", "queryScope": "COLLECTION_GROUP"},
                ],
            }
        ],
    }
    diff = diff_indexes(ttl_override, [live_composite], [live_field, default_star])
    check(
        "override dropping default CONTAINS is delete",
        any("ttlAt" in line and "CONTAINS" in line for line in diff["field_deletes"]),
        str(diff["field_deletes"]),
    )
    check(
        "override adding CG is add",
        any("ttlAt" in line and "COLLECTION_GROUP" in line for line in diff["field_adds"]),
        str(diff["field_adds"]),
    )

    # Density omitted in the file still matches SPARSE_ALL on prod
    no_density = {
        "indexes": [
            {
                "collectionGroup": "widgets",
                "queryScope": "COLLECTION",
                "fields": [
                    {"fieldPath": "status", "order": "ASCENDING"},
                    {"fieldPath": "createdAt", "order": "DESCENDING"},
                ],
            }
        ],
        "fieldOverrides": matched["fieldOverrides"],
    }
    diff = diff_indexes(no_density, [live_composite], [live_field, default_star])
    check(
        "missing density matches SPARSE_ALL",
        not diff["composite_deletes"] and not diff["composite_adds"],
        str(diff),
    )

    if failures:
        print(f"self-test failed ({len(failures)}):", file=sys.stderr)
        for row in failures:
            print(f"  - {row}", file=sys.stderr)
        return 1
    print("ok: self-test passed")
    return 0


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def _print_report(diff: dict[str, list[str] | str], project: str, path: str) -> None:
    deletes = list(diff["composite_deletes"]) + list(diff["field_deletes"])
    adds = list(diff["composite_adds"]) + list(diff["field_adds"])
    print(
        f"Compared {path} with prod {project} (read-only). "
        f"file composites={diff['file_composite_count']} "
        f"prod composites={diff['prod_composite_count']} "
        f"file overrides={diff['file_override_count']} "
        f"prod overrides={diff['prod_override_count']}."
    )
    if deletes:
        print(f"\nWOULD DELETE {len(deletes)} prod index(es) or override(s):")
        for line in deletes:
            print(f"  - {line}")
    if adds:
        print(f"\nWould ADD {len(adds)} index(es) or override(s) (not a failure):")
        for line in adds:
            print(f"  - {line}")
    if not deletes and not adds:
        print("ok: firestore.indexes.json matches prod (zero differences).")
    elif not deletes:
        print("\nok: no prod indexes would be deleted.")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--indexes", default=default_indexes_path(), help="Path to firestore.indexes.json")
    parser.add_argument("--project", default=os.environ.get("FIREBASE_PROJECT_ID") or PROD_PROJECT)
    parser.add_argument("--database", default=DEFAULT_DATABASE)
    parser.add_argument("--self-test", action="store_true", help="Run fixture tests and exit (no network).")
    parser.add_argument(
        "--export",
        metavar="PATH",
        help="Write a local firestore.indexes.json generated from live prod (GET only; does not deploy).",
    )
    args = parser.parse_args(argv)

    if args.self_test:
        return _self_test()

    path = args.indexes
    if not os.path.isfile(path):
        print(f"indexes file not found: {path}", file=sys.stderr)
        return 2

    try:
        with open(path, encoding="utf-8") as fh:
            file_doc = json.load(fh)
    except json.JSONDecodeError as exc:
        print(f"invalid JSON in {path}: {exc}", file=sys.stderr)
        return 2

    try:
        live_composites, live_fields = fetch_live(args.project, args.database)
    except Exception as exc:
        # Do not dump credentials if a library includes them in the message.
        text = str(exc)
        if "private_key" in text or "BEGIN PRIVATE" in text:
            text = "authentication failed (details omitted)."
        print(f"failed to list prod indexes: {text}", file=sys.stderr)
        return 2

    if args.export:
        doc = build_cli_document(live_composites, live_fields)
        export_path = args.export
        with open(export_path, "w", encoding="utf-8") as fh:
            fh.write(dump_cli_document(doc))
        print(
            f"Wrote {export_path} from live {args.project} "
            f"({len(doc['indexes'])} composites, "
            f"{len(doc['fieldOverrides'])} field overrides). "
            "No prod writes were made."
        )
        if os.path.abspath(export_path) == os.path.abspath(path):
            file_doc = doc

    diff = diff_indexes(file_doc, live_composites, live_fields)
    _print_report(diff, args.project, path)
    deletes = list(diff["composite_deletes"]) + list(diff["field_deletes"])
    return 1 if deletes else 0


if __name__ == "__main__":
    sys.exit(main())
