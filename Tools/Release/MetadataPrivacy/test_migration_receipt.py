#!/usr/bin/env python3
"""Synthetic-only tests for migration_receipt.py. No real exports inspected."""

import json
import os
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import migration_receipt as receipt

SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "migration_receipt.py")

RELEASES = json.dumps([{"id": "r1", "title": "t"}]).encode() + b"\n"
TESTERS = json.dumps(["a@example.com"]).encode() + b"\n"
ROLES = json.dumps([{"email": "a@example.com", "role": "tester"}]).encode() + b"\n"
SETTINGS = json.dumps({"showAll": True}).encode() + b"\n"
README = b"# hello\n"


def write_tree(root, files):
    for name, data in files.items():
        with open(os.path.join(root, name), "wb") as fh:
            fh.write(data)


def good_files():
    return {
        "releases.json": RELEASES,
        "testers.json": TESTERS,
        "roles.json": ROLES,
        "settings.json": SETTINGS,
        "readme.md": README,
    }


def run_cli(*argv):
    return subprocess.run(
        [sys.executable, SCRIPT, *argv],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


class MigrationReceiptTest(unittest.TestCase):
    def test_exact_match(self):
        with tempfile.TemporaryDirectory() as tmp:
            src = os.path.join(tmp, "src")
            cand = os.path.join(tmp, "cand")
            os.mkdir(src)
            os.mkdir(cand)
            write_tree(src, good_files())
            write_tree(cand, good_files())
            proc = run_cli("--source-dir", src, "--candidate-dir", cand)
            self.assertEqual(proc.returncode, 0, proc.stderr.decode())
            receipt = json.loads(proc.stdout.decode())
            self.assertEqual(receipt["version"], 1)
            self.assertEqual(receipt["verdict"], "LOCAL_EXPORTS_MATCH")
            self.assertEqual(
                [d["name"] for d in receipt["documents"]],
                ["releases.json", "testers.json", "roles.json", "settings.json", "readme.md"],
            )
            for doc in receipt["documents"]:
                self.assertIn("bytes", doc)
                self.assertIn("sha256", doc)
                self.assertNotIn("contents", doc)
            blob = proc.stdout.decode()
            self.assertNotIn(src, blob)
            self.assertNotIn(cand, blob)

    def test_differing_bytes_despite_equivalent_json(self):
        with tempfile.TemporaryDirectory() as tmp:
            src = os.path.join(tmp, "src")
            cand = os.path.join(tmp, "cand")
            os.mkdir(src)
            os.mkdir(cand)
            a = good_files()
            b = good_files()
            b["releases.json"] = b'[ {"id" : "r1" , "title" : "t"} ]\n'
            # Sanity: semantically equivalent but byte-different.
            self.assertEqual(json.loads(a["releases.json"]), json.loads(b["releases.json"]))
            self.assertNotEqual(a["releases.json"], b["releases.json"])
            write_tree(src, a)
            write_tree(cand, b)
            out = os.path.join(tmp, "receipt.json")
            proc = run_cli("--source-dir", src, "--candidate-dir", cand, "--out", out)
            self.assertNotEqual(proc.returncode, 0)
            self.assertIn("releases.json", proc.stderr.decode())
            self.assertFalse(os.path.lexists(out))

    def test_missing_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            src = os.path.join(tmp, "src")
            cand = os.path.join(tmp, "cand")
            os.mkdir(src)
            os.mkdir(cand)
            a = good_files()
            b = good_files()
            del b["roles.json"]
            write_tree(src, a)
            write_tree(cand, b)
            proc = run_cli("--source-dir", src, "--candidate-dir", cand)
            self.assertNotEqual(proc.returncode, 0)
            self.assertIn("roles.json", proc.stderr.decode())

    def test_corrupt_json(self):
        with tempfile.TemporaryDirectory() as tmp:
            src = os.path.join(tmp, "src")
            cand = os.path.join(tmp, "cand")
            os.mkdir(src)
            os.mkdir(cand)
            a = good_files()
            b = good_files()
            b["testers.json"] = b'["a@example.com"\n'
            write_tree(src, a)
            write_tree(cand, b)
            proc = run_cli("--source-dir", src, "--candidate-dir", cand)
            self.assertNotEqual(proc.returncode, 0)
            self.assertIn("testers.json", proc.stderr.decode())

    def test_incorrect_root_shape(self):
        cases = [
            ("releases.json", b'{"id": "r1"}\n'),
            ("testers.json", b'{"a": 1}\n'),
            ("roles.json", b'{"a": 1}\n'),
            ("settings.json", b'["showAll"]\n'),
        ]
        for name, bad in cases:
            with self.subTest(name=name):
                with tempfile.TemporaryDirectory() as tmp:
                    src = os.path.join(tmp, "src")
                    cand = os.path.join(tmp, "cand")
                    os.mkdir(src)
                    os.mkdir(cand)
                    a = good_files()
                    write_tree(src, a)
                    write_tree(cand, a)
                    with open(os.path.join(cand, name), "wb") as fh:
                        fh.write(bad)
                    # Counterpart must differ or match? Make both bad so shape
                    # (not byte-diff) is the reported failure.
                    with open(os.path.join(src, name), "wb") as fh:
                        fh.write(bad)
                    proc = run_cli("--source-dir", src, "--candidate-dir", cand)
                    self.assertNotEqual(proc.returncode, 0)
                    self.assertIn(name, proc.stderr.decode())

    def test_invalid_utf8(self):
        with tempfile.TemporaryDirectory() as tmp:
            src = os.path.join(tmp, "src")
            cand = os.path.join(tmp, "cand")
            os.mkdir(src)
            os.mkdir(cand)
            a = good_files()
            a["readme.md"] = b"\xff\xfe invalid \x80\n"
            write_tree(src, a)
            write_tree(cand, a)
            proc = run_cli("--source-dir", src, "--candidate-dir", cand)
            self.assertNotEqual(proc.returncode, 0)
            self.assertIn("readme.md", proc.stderr.decode())

    def test_symlink_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            src = os.path.join(tmp, "src")
            cand = os.path.join(tmp, "cand")
            os.mkdir(src)
            os.mkdir(cand)
            a = good_files()
            write_tree(src, a)
            write_tree(cand, a)
            target = os.path.join(cand, "roles.json")
            os.unlink(target)
            os.symlink(os.path.join(src, "roles.json"), target)
            proc = run_cli("--source-dir", src, "--candidate-dir", cand)
            self.assertNotEqual(proc.returncode, 0)
            self.assertIn("roles.json", proc.stderr.decode())

    def test_oversized_input(self):
        with tempfile.TemporaryDirectory() as tmp:
            src = os.path.join(tmp, "src")
            cand = os.path.join(tmp, "cand")
            os.mkdir(src)
            os.mkdir(cand)
            a = good_files()
            big = b"a" * (8 * 1024 * 1024 + 1)
            a["readme.md"] = big
            write_tree(src, a)
            write_tree(cand, a)
            proc = run_cli("--source-dir", src, "--candidate-dir", cand)
            self.assertNotEqual(proc.returncode, 0)
            self.assertIn("readme.md", proc.stderr.decode())

    def test_existing_output_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            src = os.path.join(tmp, "src")
            cand = os.path.join(tmp, "cand")
            os.mkdir(src)
            os.mkdir(cand)
            write_tree(src, good_files())
            write_tree(cand, good_files())
            out = os.path.join(tmp, "receipt.json")
            with open(out, "w") as fh:
                fh.write("sentinel")
            proc = run_cli("--source-dir", src, "--candidate-dir", cand, "--out", out)
            self.assertNotEqual(proc.returncode, 0)
            with open(out) as fh:
                self.assertEqual(fh.read(), "sentinel")

    def test_existing_output_symlink_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            src = os.path.join(tmp, "src")
            cand = os.path.join(tmp, "cand")
            os.mkdir(src)
            os.mkdir(cand)
            write_tree(src, good_files())
            write_tree(cand, good_files())
            real = os.path.join(tmp, "real.json")
            with open(real, "w") as fh:
                fh.write("sentinel")
            link = os.path.join(tmp, "link.json")
            os.symlink(real, link)
            proc = run_cli("--source-dir", src, "--candidate-dir", cand, "--out", link)
            self.assertNotEqual(proc.returncode, 0)
            with open(real) as fh:
                self.assertEqual(fh.read(), "sentinel")

    def test_no_receipt_on_failure(self):
        with tempfile.TemporaryDirectory() as tmp:
            src = os.path.join(tmp, "src")
            cand = os.path.join(tmp, "cand")
            os.mkdir(src)
            os.mkdir(cand)
            a = good_files()
            b = good_files()
            b["settings.json"] = json.dumps({"showAll": False}).encode() + b"\n"
            write_tree(src, a)
            write_tree(cand, b)
            out = os.path.join(tmp, "receipt.json")
            proc = run_cli("--source-dir", src, "--candidate-dir", cand, "--out", out)
            self.assertNotEqual(proc.returncode, 0)
            self.assertNotIn("LOCAL_EXPORTS_MATCH", proc.stdout.decode())
            self.assertFalse(os.path.lexists(out))

    def test_nonstandard_json_refused(self):
        for value in [b'{"value":NaN}', b'{"value":Infinity}', b'{"value":-Infinity}']:
            with self.subTest(value=value), self.assertRaises(receipt.ReceiptFailure):
                receipt._validate_text_and_shape("settings.json", value)

    def test_failed_write_leaves_no_receipt(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = os.path.join(tmp, "receipt.json")
            with patch.object(receipt.os, "fsync", side_effect=OSError("synthetic disk failure")):
                with self.assertRaises(receipt.ReceiptFailure):
                    receipt.write_exclusive(out, b'{"verdict":"LOCAL_EXPORTS_MATCH"}')
            self.assertFalse(os.path.lexists(out))
            self.assertEqual(os.listdir(tmp), [])

    def test_successful_output_complete(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = os.path.join(tmp, "receipt.json")
            receipt.write_exclusive(out, b'{"version":1}\n')
            with open(out, "rb") as output:
                self.assertEqual(output.read(), b'{"version":1}\n')
            self.assertEqual(os.listdir(tmp), ["receipt.json"])


if __name__ == "__main__":
    unittest.main()
