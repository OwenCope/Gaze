#!/usr/bin/env python3
"""Offline private-metadata migration receipt.

Compares two explicit local export directories file-by-file (exact bytes)
and emits a versioned JSON receipt on success. Performs no copy, no network,
no Blob calls, no production access, and no deployment.

Fixed document set:
  releases.json, testers.json, roles.json, settings.json, readme.md

Usage:
  python3 migration_receipt.py --source-dir DIR --candidate-dir DIR [--out receipt.json]
"""

import argparse
import hashlib
import json
import os
import stat
import sys
import tempfile

RECEIPT_VERSION = 1
VERDICT_MATCH = "LOCAL_EXPORTS_MATCH"

DOCUMENTS = (
    "releases.json",
    "testers.json",
    "roles.json",
    "settings.json",
    "readme.md",
)

JSON_DOCUMENTS = frozenset(
    ("releases.json", "testers.json", "roles.json", "settings.json")
)

# Root-shape requirements: releases/testers/roles must be JSON arrays,
# settings must be a JSON object. readme.md is UTF-8 text (no JSON shape).
ARRAY_ROOTS = frozenset(("releases.json", "testers.json", "roles.json"))
OBJECT_ROOTS = frozenset(("settings.json",))

MAX_BYTES = 8 * 1024 * 1024  # 8 MiB per file


class ReceiptFailure(Exception):
    """A verification failure tied to a fixed document name (or a global step)."""

    def __init__(self, name, reason):
        super().__init__("%s: %s" % (name, reason))
        self.name = name
        self.reason = reason


def _refuse_symlink_dir(label, path):
    try:
        st = os.lstat(path)
    except FileNotFoundError:
        raise ReceiptFailure("-", "%s directory does not exist" % label)
    except OSError as exc:
        raise ReceiptFailure("-", "%s directory unreadable: %s" % (label, exc.strerror or exc))
    if stat.S_ISLNK(st.st_mode):
        raise ReceiptFailure("-", "%s directory is a symlink; refusing" % label)
    if not stat.S_ISDIR(st.st_mode):
        raise ReceiptFailure("-", "%s directory is not a directory" % label)


def _stable_key(st):
    return (st.st_dev, st.st_ino, st.st_size, st.st_mtime_ns, st.st_ctime_ns)


def _read_regular_file_bytes(label, full_path, name):
    """Read a regular file without following symlinks; detect change during read."""
    try:
        st = os.lstat(full_path)
    except FileNotFoundError:
        raise ReceiptFailure(name, "missing in %s dir; never inferred as empty" % label)
    except OSError:
        raise ReceiptFailure(name, "unreadable in %s dir" % label)
    if stat.S_ISLNK(st.st_mode):
        raise ReceiptFailure(name, "symlink refused in %s dir" % label)
    if stat.S_ISDIR(st.st_mode):
        raise ReceiptFailure(name, "is a directory in %s dir; expected a regular file" % label)
    if not stat.S_ISREG(st.st_mode):
        raise ReceiptFailure(name, "not a regular file in %s dir; refusing" % label)
    if st.st_size > MAX_BYTES:
        raise ReceiptFailure(name, "exceeds 8 MiB cap in %s dir; refusing" % label)

    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    try:
        fd = os.open(full_path, flags)
    except FileNotFoundError:
        raise ReceiptFailure(name, "missing in %s dir; never inferred as empty" % label)
    except OSError as exc:
        import errno

        if exc.errno in (errno.ELOOP, errno.EMLINK):
            raise ReceiptFailure(name, "symlink refused in %s dir" % label)
        if exc.errno == errno.EISDIR:
            raise ReceiptFailure(name, "is a directory in %s dir; expected a regular file" % label)
        raise ReceiptFailure(name, "unreadable in %s dir" % label)
    try:
        before = os.fstat(fd)
        if not stat.S_ISREG(before.st_mode):
            raise ReceiptFailure(name, "not a regular file in %s dir; refusing" % label)
        if before.st_size > MAX_BYTES:
            raise ReceiptFailure(name, "exceeds 8 MiB cap in %s dir; refusing" % label)
        chunks = []
        total = 0
        while True:
            chunk = os.read(fd, 65536)
            if not chunk:
                break
            chunks.append(chunk)
            total += len(chunk)
            if total > MAX_BYTES:
                raise ReceiptFailure(name, "exceeds 8 MiB cap in %s dir; refusing" % label)
        after = os.fstat(fd)
        if (_stable_key(st) != _stable_key(before) or _stable_key(before) != _stable_key(after)
                or _stable_key(after) != _stable_key(os.lstat(full_path))):
            raise ReceiptFailure(name, "changed during reading in %s dir; refusing" % label)
        return b"".join(chunks)
    except OSError:
        raise ReceiptFailure(name, "read failed or file changed in %s dir; refusing" % label)
    finally:
        os.close(fd)


def _validate_text_and_shape(name, data):
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        raise ReceiptFailure(name, "invalid UTF-8; refusing")
    if name not in JSON_DOCUMENTS:
        return
    try:
        def reject_constant(_):
            raise ValueError("nonstandard JSON constant")
        parsed = json.loads(text, parse_constant=reject_constant)
    except (ValueError, RecursionError):
        raise ReceiptFailure(name, "malformed JSON; refusing")
    if name in ARRAY_ROOTS and not isinstance(parsed, list):
        raise ReceiptFailure(name, "incorrect root shape; expected a JSON array")
    if name in OBJECT_ROOTS and (not isinstance(parsed, dict)):
        raise ReceiptFailure(name, "incorrect root shape; expected a JSON object")


def compare_dirs(source_dir, candidate_dir):
    """Return list of (name, byte_count, sha256). Raise ReceiptFailure on mismatch."""
    _refuse_symlink_dir("source", source_dir)
    _refuse_symlink_dir("candidate", candidate_dir)
    entries = []
    for name in DOCUMENTS:
        src_bytes = _read_regular_file_bytes(
            "source", os.path.join(source_dir, name), name
        )
        cand_bytes = _read_regular_file_bytes(
            "candidate", os.path.join(candidate_dir, name), name
        )
        _validate_text_and_shape(name, src_bytes)
        _validate_text_and_shape(name, cand_bytes)
        if src_bytes != cand_bytes:
            raise ReceiptFailure(name, "bytes differ between local exports; refusing")
        entries.append(
            (name, len(src_bytes), hashlib.sha256(src_bytes).hexdigest())
        )
    return entries


def build_receipt(entries):
    return {
        "version": RECEIPT_VERSION,
        "verdict": VERDICT_MATCH,
        "documents": [
            {"name": name, "bytes": count, "sha256": digest}
            for name, count, digest in entries
        ],
    }


def write_exclusive(path, payload_bytes):
    # Publish only a complete, synced file, with a no-overwrite hard link.
    temporary = None
    try:
        fd, temporary = tempfile.mkstemp(prefix=".gaze-receipt-", dir=os.path.dirname(path) or ".")
        with os.fdopen(fd, "wb") as output:
            output.write(payload_bytes)
            output.flush()
            os.fsync(output.fileno())
        os.link(temporary, path)
    except FileExistsError:
        raise ReceiptFailure("-", "--out already exists; refusing to overwrite")
    except OSError:
        raise ReceiptFailure("-", "--out could not be written; no receipt published")
    finally:
        if temporary is not None:
            os.unlink(temporary)


def parse_args(argv):
    parser = argparse.ArgumentParser(
        description="Byte-for-byte comparison of local metadata exports; "
        "emits a versioned receipt. No copy, no network, no remote action."
    )
    parser.add_argument("--source-dir", required=True, help="explicit local export directory")
    parser.add_argument("--candidate-dir", required=True, help="explicit local export directory")
    parser.add_argument("--out", required=False, default=None, help="new receipt file (never overwritten)")
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(argv)
    try:
        entries = compare_dirs(args.source_dir, args.candidate_dir)
    except ReceiptFailure as exc:
        print("%s: %s" % (exc.name, exc.reason), file=sys.stderr)
        return 1
    receipt = build_receipt(entries)
    payload = (json.dumps(receipt, indent=2, sort_keys=False) + "\n").encode("utf-8")
    if args.out is not None:
        try:
            write_exclusive(args.out, payload)
        except ReceiptFailure as exc:
            print("%s: %s" % (exc.name, exc.reason), file=sys.stderr)
            return 1
    sys.stdout.write(payload.decode("utf-8"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
