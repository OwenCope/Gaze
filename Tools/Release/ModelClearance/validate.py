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
import sys

DISCLAIMER = (
    "This validator checks recorded evidence and byte identity only; "
    "it does not make a legal determination and grants no rights."
)

SCHEMA = "gaze-model-clearance/1"
MODEL_SUFFIXES = (".mlmodel", ".mlpackage")


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def check_evidence(inv):
    """Refuse on missing entries, unclear clearance, or incomplete evidence."""
    reasons = []
    required = inv.get("requiredArtifacts", [])
    scopes = set(inv.get("requiredScopes", []))
    by_id = {a.get("id"): a for a in inv.get("artifacts", [])}
    for rid in required:
        a = by_id.get(rid)
        if a is None:
            reasons.append("missing clearance entry: %s" % rid)
            continue
        if a.get("clearance") != "cleared":
            reasons.append(
                "uncleared artifact: %s (clearance=%r)"
                % (rid, a.get("clearance"))
            )
            continue
        prov = a.get("provenance", {})
        if not prov.get("evidenceRefs"):
            reasons.append("no provenance evidence refs: %s" % rid)
        lic = a.get("license", {})
        if not lic.get("grant"):
            reasons.append("no licence/grant recorded: %s" % rid)
        if not lic.get("evidenceRefs"):
            reasons.append("no licence evidence refs: %s" % rid)
        missing = scopes - set(lic.get("redistributionScope", []))
        if missing:
            reasons.append(
                "incomplete redistribution scope for %s: missing %s"
                % (rid, sorted(missing))
            )
    return reasons


def check_bytes(inv, root):
    """Refuse when a recorded file is missing, resized, or re-hashed."""
    reasons = []
    for a in inv.get("artifacts", []):
        for f in a.get("byteIdentity", {}).get("files", []):
            rel = f.get("path", "")
            disk = os.path.join(root, rel)
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
    """Refuse when a model file under Resources has no clearance entry."""
    known = set()
    for a in inv.get("artifacts", []):
        for f in a.get("byteIdentity", {}).get("files", []):
            known.add(f.get("path", ""))
        for p in a.get("repoPaths", []):
            known.add(p)
    reasons = []
    res = os.path.join(root, "Resources")
    if not os.path.isdir(res):
        return ["Resources/ directory missing"]
    for dirpath, _dirnames, filenames in os.walk(res):
        # Compiled outputs are build products, not clearance subjects.
        if dirpath.endswith(".mlmodelc") or ".mlmodelc/" in dirpath:
            continue
        for name in filenames:
            full = os.path.join(dirpath, name)
            rel = os.path.relpath(full, root)
            if rel.endswith(MODEL_SUFFIXES):
                if rel not in known and not _covered_by_dir(rel, known):
                    reasons.append("model file without clearance entry: %s" % rel)
        # An .mlpackage whose files are all known is covered; a stray
        # top-level .mlpackage dir that is not referenced at all is not.
        for name in _dirnames:
            if name.endswith(".mlpackage"):
                rel = os.path.join(os.path.relpath(dirpath, root), name)
                if rel not in known and not any(
                    k == rel or k.startswith(rel + "/") for k in known
                ):
                    reasons.append(
                        "model package without clearance entry: %s" % rel
                    )
    return reasons


def _covered_by_dir(rel, known):
    parts = rel.split(os.sep)
    for i in range(1, len(parts)):
        if os.sep.join(parts[:i]) in known:
            return True
    return False


def validate(inventory_path, root, check_disk=True):
    reasons = []
    try:
        with open(inventory_path, "r", encoding="utf-8") as f:
            inv = json.load(f)
    except (OSError, ValueError) as e:
        return False, ["cannot read inventory: %s" % e]
    if inv.get("schema") != SCHEMA:
        reasons.append("unknown inventory schema: %r" % inv.get("schema"))
        return False, reasons
    reasons.extend(check_evidence(inv))
    if check_disk:
        reasons.extend(check_bytes(inv, root))
        reasons.extend(check_coverage(inv, root))
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
    verdict = "PASS" if ok else "REFUSE"
    if args.json:
        print(json.dumps({"verdict": verdict, "reasons": reasons,
                          "disclaimer": DISCLAIMER}, indent=2))
    else:
        print("%s: model clearance" % verdict)
        for r in reasons:
            print("  - %s" % r)
        print(DISCLAIMER)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
