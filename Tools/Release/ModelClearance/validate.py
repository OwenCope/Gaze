#!/usr/bin/env python3
"""Gaze model-clearance validator.

Checks that clearance.json records complete evidence for every required
artifact AND that the recorded byte identity matches the files on disk.

This checks recorded evidence and byte identity only. It does NOT make a
legal determination and does NOT grant any rights (see DISCLAIMER).

Preflight interface (for Pip / release preflight):
    python3 Tools/Release/ModelClearance/validate.py \
        [--inventory Tools/Release/ModelClearance/clearance.json] \
        [--root <repo-root>] [--skip-bytes] [--json]

Exit 0 (PASS) only when every required artifact is cleared with complete
evidence and every recorded hash matches. Any other outcome exits 1
(REFUSE) with reasons on stdout (or JSON with --json).
"""

import argparse
import hashlib
import json
import os
import re
from pathlib import Path
import sys

DISCLAIMER = (
    "This validator checks recorded evidence and byte identity only; "
    "it does not make a legal determination and grants no rights."
)

SCHEMA = "gaze-model-clearance/1"
MODEL_SUFFIXES = (".mlmodel", ".mlpackage", ".mlmodelc")


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def check_evidence(inv):
    """Require a nonempty, explicit inventory; directory names are not byte evidence."""
    reasons = []
    required = inv.get("requiredArtifacts")
    scopes = inv.get("requiredScopes")
    artifacts = inv.get("artifacts")
    def strings(value):
        return isinstance(value, list) and bool(value) and all(isinstance(v, str) and v.strip() for v in value)
    if not strings(required) or not strings(scopes) or not isinstance(artifacts, list) or not artifacts:
        return ["inventory requires nonempty artifacts, requiredArtifacts and requiredScopes"]
    if not all(isinstance(a, dict) and isinstance(a.get("id"), str) and a["id"].strip() for a in artifacts):
        return ["invalid artifact entry"]
    ids = [a["id"] for a in artifacts]
    if len(ids) != len(set(ids)) or len(required) != len(set(required)):
        reasons.append("duplicate artifact identifiers")
    for rid in set(required) - set(ids):
        reasons.append("missing clearance entry: %s" % rid)
    for a in artifacts:
        rid = a["id"]
        if a.get("clearance") != "cleared":
            reasons.append("uncleared artifact: %s (clearance=%r)" % (rid, a.get("clearance")))
        prov, lic = a.get("provenance", {}), a.get("license", {})
        if not isinstance(prov, dict) or not strings(prov.get("evidenceRefs")):
            reasons.append("no provenance evidence refs: %s" % rid)
        if not isinstance(lic, dict):
            reasons.append("invalid licence record: %s" % rid)
            continue
        if not isinstance(lic.get("grant"), str) or not lic["grant"].strip():
            reasons.append("no licence/grant recorded: %s" % rid)
        if not strings(lic.get("evidenceRefs")):
            reasons.append("no licence evidence refs: %s" % rid)
        covered_scopes = lic.get("redistributionScope", [])
        if not strings(covered_scopes) or not set(scopes).issubset(set(covered_scopes)):
            reasons.append("incomplete redistribution scope for %s" % rid)
        identity = a.get("byteIdentity", {})
        files = identity.get("files") if isinstance(identity, dict) else None
        if not isinstance(files, list) or not files:
            reasons.append("no byte identity files: %s" % rid)
            continue
        paths = set()
        for f in files:
            if not isinstance(f, dict):
                reasons.append("invalid byte identity record: %s" % rid)
                continue
            rel = f.get("path", "")
            if not isinstance(rel, str) or not rel.startswith("Resources/") or ".." in Path(rel).parts or rel in paths:
                reasons.append("invalid or duplicate resource path: %s" % rid)
            paths.add(rel) if isinstance(rel, str) else None
            if type(f.get("bytes")) is not int or f["bytes"] < 0 or not re.fullmatch(r"[0-9a-f]{64}", str(f.get("sha256", ""))):
                reasons.append("invalid byte identity: %s" % rid)
    return reasons


def check_bytes(inv, root):
    """Refuse when a recorded file is missing, resized, or re-hashed."""
    reasons = []
    for a in inv.get("artifacts", []):
        for f in a.get("byteIdentity", {}).get("files", []):
            rel = f.get("path", "")
            if not isinstance(rel, str) or not rel.startswith("Resources/") or ".." in Path(rel).parts:
                continue
            disk = os.path.join(root, rel)
            if not Path(disk).resolve().is_relative_to(Path(root).resolve()):
                reasons.append("resource path escapes repository: %s" % rel)
                continue
            if not os.path.isfile(disk):
                reasons.append("file missing on disk: %s" % rel)
                continue
            size = os.path.getsize(disk)
            if size != f.get("bytes"):
                reasons.append(
                    "size changed: %s (recorded %r, on disk %r)"
                    % (rel, f.get("bytes"), size)
                )
            digest = sha256_file(disk)
            if digest != f.get("sha256"):
                reasons.append(
                    "hash changed: %s (recorded %s, on disk %s)"
                    % (rel, f.get("sha256"), digest)
                )
    return reasons


def check_coverage(inv, root):
    """Every model payload and asset file needs its own recorded fingerprint."""
    known = {f.get("path") for a in inv.get("artifacts", [])
             for f in a.get("byteIdentity", {}).get("files", []) if isinstance(f, dict)}
    resources = Path(root) / "Resources"
    if not resources.is_dir():
        return ["Resources/ directory missing"]
    covered_roots = [resources / name for name in ("Art", "Credits", "AppIcon.icon")]
    covered_roots.extend(p for p in resources.rglob("*") if p.suffix in MODEL_SUFFIXES)
    expected = set()
    for path in covered_roots:
        if path.is_file():
            expected.add(path.relative_to(root).as_posix())
        elif path.is_dir():
            expected.update(f.relative_to(root).as_posix() for f in path.rglob("*") if f.is_file())
    return ["model or asset file without clearance entry: %s" % path
            for path in sorted(expected - known)]


def validate(inventory_path, root, check_disk=True):
    reasons = []
    try:
        with open(inventory_path, "r", encoding="utf-8") as f:
            inv = json.load(f)
    except (OSError, ValueError) as e:
        return False, ["cannot read inventory: %s" % e]
    if not isinstance(inv, dict):
        return False, ["inventory must be an object"]
    if inv.get("schema") != SCHEMA:
        reasons.append("unknown inventory schema: %r" % inv.get("schema"))
        return False, reasons
    reasons.extend(check_evidence(inv))
    if check_disk:
        try:
            reasons.extend(check_bytes(inv, root))
            reasons.extend(check_coverage(inv, root))
        except (OSError, TypeError, AttributeError, ValueError) as e:
            reasons.append("invalid or unreadable byte inventory: %s" % e)
    return (len(reasons) == 0), reasons


def main(argv=None):
    here = os.path.dirname(os.path.abspath(__file__))
    default_root = os.path.dirname(os.path.dirname(os.path.dirname(here)))
    ap = argparse.ArgumentParser(description="Gaze model-clearance gate.")
    ap.add_argument("--inventory", default=os.path.join(here, "clearance.json"))
    ap.add_argument("--root", default=default_root)
    ap.add_argument("--skip-bytes", action="store_true",
                    help="check evidence records only, not files on disk")
    ap.add_argument("--json", action="store_true", help="emit JSON result")
    args = ap.parse_args(argv)
    ok, reasons = validate(args.inventory, args.root,
                           check_disk=not args.skip_bytes)
    verdict = ("RECORDS_ONLY" if args.skip_bytes else "PASS") if ok else "REFUSE"
    if args.json:
        print(json.dumps({"verdict": verdict, "reasons": reasons,
                          "disclaimer": DISCLAIMER, "byteIdentityChecked": not args.skip_bytes}, indent=2))
    else:
        print("%s: model clearance" % verdict)
        for r in reasons:
            print("  - %s" % r)
        print(DISCLAIMER)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
