#!/usr/bin/env python3
"""Guards the HOLDS env PATCH: never replace the whole map, never drop GCLOUD_PROJECT."""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from holds_authority_mode_payload import UPDATE_MASK, build_patch  # noqa: E402


class PayloadTest(unittest.TestCase):
    def test_nested_mask_and_single_key_body(self):
        for mode in ("authoritative", "shadow"):
            body, mask = build_patch(mode)
            self.assertEqual(mask, UPDATE_MASK)
            self.assertEqual(mask, "environmentVariables.HOLDS_AUTHORITY_MODE")
            self.assertEqual(
                body,
                {"environmentVariables": {"HOLDS_AUTHORITY_MODE": mode}},
            )
            # A full-map replace is what deleted GCLOUD_PROJECT. The body must
            # not list any other key (including reserved ones).
            keys = set(body["environmentVariables"])
            self.assertEqual(keys, {"HOLDS_AUTHORITY_MODE"})
            self.assertNotIn("GCLOUD_PROJECT", body["environmentVariables"])
            self.assertNotIn("FIREBASE_CONFIG", body["environmentVariables"])

    def test_rejects_other_modes(self):
        with self.assertRaises(ValueError):
            build_patch("live")
        with self.assertRaises(ValueError):
            build_patch("")

    def test_existing_env_would_be_preserved(self):
        """Document the contract: a GET env with GCLOUD_PROJECT is not copied
        into the PATCH body (reserved) and is not deleted because the mask is
        a single field, not 'environmentVariables'."""
        existing = {
            "GCLOUD_PROJECT": "tashil-dev",
            "FIREBASE_CONFIG": "{}",
            "EVENTARC_CLOUD_EVENT_SOURCE": "x",
            "HOLDS_AUTHORITY_MODE": "shadow",
            "CUSTOM_FLAG": "keep-me",
        }
        body, mask = build_patch("authoritative")
        self.assertEqual(mask, "environmentVariables.HOLDS_AUTHORITY_MODE")
        # The API merges this one field; these keys are not in the body and
        # must remain on the function after the PATCH.
        for key in existing:
            if key != "HOLDS_AUTHORITY_MODE":
                self.assertNotIn(key, body["environmentVariables"])
        # Sanity: if someone switches the mask back to the whole map, this
        # test still shows the body is not a full replace of `existing`.
        self.assertNotEqual(set(body["environmentVariables"]), set(existing))


if __name__ == "__main__":
    unittest.main()
