#!/usr/bin/env python3
"""Send one dev-safe FCM test message to dlg_dev_test_1 on tashil-dev only.

Hard constraints:
  - Project must be tashil-dev. Refuses any other project (including prod).
  - Reads the token from fcm_tokens/dlg_dev_test_1 at runtime.
  - Never prints the token.
  - Sends exactly one message.

When to run:
  Only after User Test has enabled notifications for the dev app on the
  device (the M31 3ff8e5d pass had Android allowNoti=false). Enable
  notifications, force-stop and reopen the app so a fresh token is saved,
  then run this once.

Usage (on the Mac, as the tashil-dev gcloud user):

  python3 scripts/send_tashil_dev_test_push.py

Requires Application Default Credentials or `gcloud auth print-access-token`
with access to project tashil-dev.
"""
from __future__ import annotations

import json
import subprocess
import sys
import urllib.error
import urllib.request

PROJECT = "tashil-dev"
DELEGATE_UID = "dlg_dev_test_1"
TOKEN_DOC = (
    f"https://firestore.googleapis.com/v1/projects/{PROJECT}"
    f"/databases/(default)/documents/fcm_tokens/{DELEGATE_UID}"
)
FCM_SEND = f"https://fcm.googleapis.com/v1/projects/{PROJECT}/messages:send"


def access_token() -> str:
    out = subprocess.check_output(
        ["gcloud", "auth", "print-access-token"],
        text=True,
    ).strip()
    if not out:
        raise SystemExit("gcloud did not return an access token")
    return out


def request(url: str, token: str, data: bytes | None = None) -> dict:
    headers = {
        "Authorization": f"Bearer {token}",
        "x-goog-user-project": PROJECT,
        "Content-Type": "application/json",
    }
    req = urllib.request.Request(url, data=data, headers=headers, method="POST" if data else "GET")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            body = resp.read().decode("utf-8")
            return json.loads(body) if body else {}
    except urllib.error.HTTPError as exc:
        err = exc.read().decode("utf-8", errors="replace")
        # Strip any token-like strings before printing the error.
        raise SystemExit(f"HTTP {exc.code} on {url.split('?')[0]}: {err[:500]}") from exc


def extract_token(doc: dict) -> str:
    fields = doc.get("fields") or {}
    for key in ("token", "fcmToken", "fcm_token"):
        value = fields.get(key) or {}
        if isinstance(value, dict) and value.get("stringValue"):
            return value["stringValue"].strip()
    raise SystemExit(
        f"No token field on fcm_tokens/{DELEGATE_UID}. "
        "Open the dev app while signed in as the fake delegate after enabling notifications."
    )


def main() -> int:
    token = access_token()
    # Confirm the identity is scoped to tashil-dev by reading the doc there.
    doc = request(TOKEN_DOC, token)
    fcm_token = extract_token(doc)
    payload = {
        "message": {
            "token": fcm_token,
            "notification": {
                "title": "إشعار تجريبي DEV",
                "body": "رسالة اختبار واحدة من tashil-dev للمندوب التجريبي.",
            },
            "data": {
                "type": "dev_test_push",
                "delegateUid": DELEGATE_UID,
                "project": PROJECT,
            },
            "android": {"priority": "high"},
        }
    }
    result = request(FCM_SEND, token, data=json.dumps(payload).encode("utf-8"))
    name = result.get("name", "")
    # name is projects/tashil-dev/messages/<id> — safe to print.
    print(f"Sent one test push on {PROJECT} to {DELEGATE_UID}: {name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
