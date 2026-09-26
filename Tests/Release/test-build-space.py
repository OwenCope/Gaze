#!/usr/bin/env python3
"""Regression tests for the build-space guard.

Stdlib only. Never fills a disk and never invokes the native build: all
capacity scenarios use temporary directories plus mocked disk_usage/stat
results.
"""

import importlib.util
import io
import os
import tempfile
import unittest
from contextlib import redirect_stderr
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
CHECK_PATH = os.path.join(HERE, "..", "Release", "check-build-space.py")


def load_module():
    spec = importlib.util.spec_from_file_location("check_build_space", CHECK_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


cbs = load_module()
GIB = 1024 ** 3


class CheckBuildSpaceTests(unittest.TestCase):
    def test_sufficient_capacity_passes(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = os.path.join(tmp, "Gaze.app")
            with mock.patch.object(
                cbs, "free_bytes", return_value=6 * GIB
            ), mock.patch.object(cbs, "device_id", return_value=11):
                self.assertEqual(cbs.check([out, tmp]), [])
                self.assertEqual(cbs.main(["--output", out, "--temporary", tmp]), 0)

    def test_just_under_limit_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = os.path.join(tmp, "Gaze.app")
            with mock.patch.object(
                cbs, "free_bytes", return_value=cbs.REQUIRED_BYTES - 1
            ), mock.patch.object(cbs, "device_id", return_value=12):
                failures = cbs.check([out, tmp])
                self.assertEqual(len(failures), 1)
                err = io.StringIO()
                with redirect_stderr(err):
                    code = cbs.main(["--output", out, "--temporary", tmp])
                self.assertNotEqual(code, 0)
                text = err.getvalue()
                self.assertIn(out, text)
                self.assertIn("5", text)  # required GiB
                self.assertIn("no build was started", text)

    def test_exact_threshold_passes(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = os.path.join(tmp, "Gaze.app")
            with mock.patch.object(
                cbs, "free_bytes", return_value=cbs.REQUIRED_BYTES
            ), mock.patch.object(cbs, "device_id", return_value=13):
                self.assertEqual(cbs.check([out, tmp]), [])
                self.assertEqual(cbs.main(["--output", out, "--temporary", tmp]), 0)

    def test_nonexistent_nested_output_resolves_without_creating(self):
        with tempfile.TemporaryDirectory() as tmp:
            nested = os.path.join(tmp, "missing-a", "missing-b", "Gaze.app")
            anchor = cbs.nearest_existing_parent(nested)
            self.assertEqual(anchor, tmp)
            self.assertFalse(os.path.exists(os.path.join(tmp, "missing-a")))
            with mock.patch.object(
                cbs, "free_bytes", return_value=6 * GIB
            ), mock.patch.object(cbs, "device_id", return_value=14):
                self.assertEqual(cbs.main(["--output", nested, "--temporary", tmp]), 0)

    def test_duplicate_filesystem_checked_once(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = os.path.join(tmp, "Gaze.app")
            with mock.patch.object(cbs, "device_id", return_value=15) as dev, mock.patch.object(
                cbs, "free_bytes", return_value=6 * GIB
            ) as free:
                self.assertEqual(cbs.main(["--output", out, "--temporary", tmp]), 0)
                self.assertEqual(dev.call_count, 2)  # one per path for dedup key
                self.assertEqual(free.call_count, 1)  # one per distinct filesystem

    def test_inspection_failure_fails_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = os.path.join(tmp, "Gaze.app")
            with mock.patch.object(cbs, "device_id", return_value=16), mock.patch.object(
                cbs, "free_bytes", side_effect=OSError("disk unavailable")
            ):
                failures = cbs.check([out, tmp])
                self.assertEqual(len(failures), 1)
                self.assertIsNone(failures[0][1])
                err = io.StringIO()
                with redirect_stderr(err):
                    code = cbs.main(["--output", out, "--temporary", tmp])
                self.assertNotEqual(code, 0)
                text = err.getvalue()
                self.assertIn(out, text)
                self.assertIn("5", text)
                self.assertIn("no build was started", text)


if __name__ == "__main__":
    unittest.main()
