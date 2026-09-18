#!/usr/bin/env python3
"""Build-space guard for Gaze.

Refuses to start a build when the output or temporary filesystem has less
than 5 GiB free. Read-only: never creates directories, deletes anything,
or offers cleanup. No bypass flag exists by design.
"""

import argparse
import os
import shutil
import sys

REQUIRED_GIB = 5
REQUIRED_BYTES = 5 * 1024 ** 3


def nearest_existing_parent(path):
    """Return the nearest existing ancestor of path without creating anything."""
    current = os.path.abspath(path)
    while not os.path.exists(current):
        parent = os.path.dirname(current)
        if parent == current:
            return current
        current = parent
    return current


def device_id(path):
    """Return the filesystem identity (st_dev) for path."""
    return os.stat(path).st_dev


def free_bytes(path):
    """Return free bytes on the filesystem containing path."""
    return shutil.disk_usage(path).free


def gib(value_bytes):
    return value_bytes / (1024 ** 3)


def check(paths):
    """Inspect each path; return a list of (path, free_or_None, reason) failures."""
    failures = []
    seen_devices = set()
    for path in paths:
        try:
            anchor = nearest_existing_parent(path)
            dev = device_id(anchor)
        except OSError as exc:
            failures.append((path, None, str(exc)))
            continue
        if dev in seen_devices:
            continue
        seen_devices.add(dev)
        try:
            free = free_bytes(anchor)
        except OSError as exc:
            failures.append((path, None, str(exc)))
            continue
        if free < REQUIRED_BYTES:
            failures.append((path, free, "insufficient free space"))
    return failures


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Refuse a Gaze build when disk space is below 5 GiB."
    )
    parser.add_argument("--output", required=True, help="Final app bundle path.")
    parser.add_argument(
        "--temporary", required=True, help="Temporary/staging directory path."
    )
    args = parser.parse_args(argv)
    paths = [args.output, args.temporary]
    failures = check(paths)
    if failures:
        for path, free, reason in failures:
            if free is None:
                print(
                    "build-space check failed for %s: %s; "
                    "required %.1f GiB; no build was started."
                    % (path, reason, float(REQUIRED_GIB)),
                    file=sys.stderr,
                )
            else:
                print(
                    "build-space check failed for %s: only %.2f GiB available "
                    "(%s); required %.1f GiB; no build was started."
                    % (path, gib(free), reason, float(REQUIRED_GIB)),
                    file=sys.stderr,
                )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
