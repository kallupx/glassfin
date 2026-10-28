#!/usr/bin/env python3
"""Fail before upload if any explicitly named benchmark result contains credentials.

Files are read only. Missing/unreadable files, directories, symlinks, globs and
xcresult bundles fail closed; this script never discovers or rewrites artifacts.
"""

from __future__ import annotations

import argparse
import re
import sys
import unittest
from pathlib import Path

CREDENTIAL = re.compile(
    r"api_?key|access_?token|authorization|x-emby-token|\b(?:token|password|pw|secret)\b",
    re.IGNORECASE,
)


def scan(paths: list[Path]) -> int:
    if not paths:
        print("benchmark scan: no result files supplied", file=sys.stderr)
        return 1
    failed = False
    for path in paths:
        if (
            any(character in str(path) for character in "*?[]{}!")
            or any(part.lower().endswith(".xcresult") for part in path.parts)
            or path.suffix.lower() not in {".json", ".csv"}
            or any(part.is_symlink() for part in (path, *path.absolute().parents))
            or not path.is_file()
        ):
            print(f"benchmark scan: {path}: expected an explicit regular JSON/CSV file", file=sys.stderr)
            failed = True
            continue
        try:
            contents = path.read_text(encoding="utf-8")
        except (OSError, UnicodeError):
            print(f"benchmark scan: {path}: cannot read UTF-8 result file", file=sys.stderr)
            failed = True
            continue
        if CREDENTIAL.search(contents):
            # Never echo matching contents, which can themselves contain secrets.
            print(f"benchmark scan: {path}: credential marker found; upload blocked", file=sys.stderr)
            failed = True
    if failed:
        return 1
    print(f"benchmark scan: passed ({len(paths)} files)")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("files", nargs="*", type=Path)
    args = parser.parse_args()
    if args.self_test:
        suite = unittest.defaultTestLoader.discover(
            str(Path(__file__).parent), pattern="test_scan_benchmark_artifacts.py"
        )
        if suite.countTestCases() == 0:
            print("benchmark scan: self-test suite is missing", file=sys.stderr)
            return 1
        return 0 if unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful() else 1
    if not args.files:
        parser.error("provide every result file to be uploaded")
    return scan(args.files)


if __name__ == "__main__":
    raise SystemExit(main())
