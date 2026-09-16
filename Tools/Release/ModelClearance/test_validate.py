#!/usr/bin/env python3
"""Tests for the model-clearance validator (validate.py).

All fixtures are synthetic: temp files with invented bytes and a temp
inventory pointing at them. Nothing here touches real weights or grants,
and nothing here clears the real gate.
"""

import copy
import hashlib
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import validate


def _write(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(data)


def _entry(aid, digest, size, clearance="cleared", grant="synthetic test grant",
           refs=("test/evidence.txt",), scopes=("bundled-app-distribution",)):
    return {
        "id": aid,
        "kind": "ml-model",
        "description": "synthetic",
        "repoPaths": ["Resources/%s.bin" % aid],
        "bundledAs": "synthetic",
        "byteIdentity": {"files": [
            {"path": "Resources/%s.bin" % aid,
             "bytes": size, "sha256": digest}]},
        "provenance": {"summary": "synthetic",
                       "evidenceRefs": list(refs), "status": "synthetic"},
        "license": {"summary": "synthetic", "grant": grant,
                    "evidenceRefs": list(refs),
                    "redistributionScope": list(scopes),
                    "status": "synthetic"},
        "clearance": clearance,
        "notes": "synthetic",
    }


class ClearanceTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = self.tmp.name
        os.makedirs(os.path.join(self.root, "Resources"))
        self.payloads = {
            "face-embedding": b"synthetic-face-weights",
            "spoof-detector": b"synthetic-spoof-weights",
        }
        self.inv = {
            "schema": "gaze-model-clearance/1",
            "generated": "synthetic",
            "requiredScopes": ["bundled-app-distribution"],
            "requiredArtifacts": ["face-embedding", "spoof-detector"],
            "artifacts": [],
        }
        for aid, data in self.payloads.items():
            _write(os.path.join(self.root, "Resources", aid + ".bin"), data)
            self.inv["artifacts"].append(_entry(
                aid, hashlib.sha256(data).hexdigest(), len(data)))
        self.inv_path = os.path.join(self.root, "clearance.json")
        self._save()

    def tearDown(self):
        self.tmp.cleanup()

    def _save(self):
        with open(self.inv_path, "w", encoding="utf-8") as f:
            json.dump(self.inv, f)

    def _validate(self):
        return validate.validate(self.inv_path, self.root, check_disk=True)

    def test_complete_synthetic_evidence_accepted(self):
        ok, reasons = self._validate()
        self.assertTrue(ok, reasons)
        self.assertEqual(reasons, [])

    def test_missing_clearance_refused(self):
        self.inv["artifacts"][0]["clearance"] = "unresolved"
        self._save()
        ok, reasons = self._validate()
        self.assertFalse(ok)
        self.assertTrue(any("uncleared artifact: face-embedding" in r
                            for r in reasons), reasons)

    def test_missing_entry_refused(self):
        self.inv["artifacts"] = [a for a in self.inv["artifacts"]
                                 if a["id"] != "spoof-detector"]
        self._save()
        ok, reasons = self._validate()
        self.assertFalse(ok)
        self.assertTrue(any("missing clearance entry: spoof-detector" in r
                            for r in reasons), reasons)

    def test_changed_hash_refused(self):
        _write(os.path.join(self.root, "Resources", "face-embedding.bin"),
               b"tampered-bytes-different-content!!")
        ok, reasons = self._validate()
        self.assertFalse(ok)
        self.assertTrue(any("hash changed" in r and "face-embedding" in r
                            for r in reasons), reasons)

    def test_incomplete_scope_refused(self):
        self.inv["artifacts"][1]["license"]["redistributionScope"] = [
            "internal-testing-only"]
        self._save()
        ok, reasons = self._validate()
        self.assertFalse(ok)
        self.assertTrue(any("incomplete redistribution scope" in r
                            and "spoof-detector" in r for r in reasons),
                        reasons)

    def test_missing_grant_refused(self):
        other = copy.deepcopy(self.inv)
        other["artifacts"][0]["license"]["grant"] = ""
        other["artifacts"][0]["license"]["evidenceRefs"] = []
        with open(self.inv_path, "w", encoding="utf-8") as f:
            json.dump(other, f)
        ok, reasons = self._validate()
        self.assertFalse(ok)
        self.assertTrue(any("no licence/grant recorded: face-embedding" in r
                            for r in reasons), reasons)

    def test_uncovered_model_file_refused(self):
        _write(os.path.join(self.root, "Resources", "Liveness.mlmodel"),
               b"synthetic-unlisted-model")
        ok, reasons = self._validate()
        self.assertFalse(ok)
        self.assertTrue(any("without clearance entry" in r
                            and "Liveness.mlmodel" in r for r in reasons),
                        reasons)

    def test_empty_inventory_refused(self):
        self.inv['requiredArtifacts'] = []
        self.inv['artifacts'] = []
        self._save()
        self.assertFalse(self._validate()[0])

    def test_unhashed_directory_does_not_cover_payload(self):
        self.inv['artifacts'][0]['repoPaths'] = ['Resources']
        _write(os.path.join(self.root, 'Resources', 'Other.mlmodelc', 'model.bin'), b'new')
        self._save()
        self.assertFalse(self._validate()[0])

    def test_new_asset_refused(self):
        _write(os.path.join(self.root, 'Resources', 'Art', 'new.png'), b'new image')
        self.assertFalse(self._validate()[0])

    def test_package_metadata_requires_fingerprint(self):
        _write(os.path.join(self.root, 'Resources', 'Model.mlpackage', 'Manifest.json'), b'{}')
        self.inv['artifacts'][0]['repoPaths'].append('Resources/Model.mlpackage')
        self._save()
        self.assertFalse(self._validate()[0])

    def test_missing_byte_identity_refused(self):
        self.inv['artifacts'][0]['byteIdentity']['files'] = []
        self._save()
        self.assertFalse(self._validate()[0])

    def test_duplicate_id_refused(self):
        self.inv['artifacts'].append(copy.deepcopy(self.inv['artifacts'][0]))
        self._save()
        self.assertFalse(self._validate()[0])

    def test_path_escape_refused(self):
        self.inv['artifacts'][0]['byteIdentity']['files'][0]['path'] = '../outside'
        self._save()
        self.assertFalse(self._validate()[0])

    def test_blank_evidence_refused(self):
        self.inv['artifacts'][0]['license']['grant'] = '  '
        self._save()
        self.assertFalse(self._validate()[0])


if __name__ == "__main__":
    unittest.main()
