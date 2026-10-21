#!/usr/bin/env python3
"""Fail when `uitest-` or `MockAPIClient` is compiled into a Release source file.

The strings may appear inside `#if DEBUG` and inside test or UI-test sources.
"""

from __future__ import annotations

import sys
from pathlib import Path

NEEDLES = ("uitest-", "MockAPIClient")
SKIP_PARTS = {"Tests", "UITests", ".build", "checkouts"}


def release_includes(lines: list[str]) -> list[tuple[int, str]]:
    """Return lines that survive when DEBUG is not defined."""
    included = [True]
    hits: list[tuple[int, str]] = []
    for number, line in enumerate(lines, start=1):
        stripped = line.strip()
        if stripped.startswith("#if"):
            condition = stripped[3:].strip()
            parent = included[-1]
            included.append(parent and release_condition(condition))
            continue
        if stripped.startswith("#elseif"):
            parent = included[-2] if len(included) > 1 else True
            included[-1] = parent and release_condition(stripped[7:].strip())
            continue
        if stripped.startswith("#else"):
            parent = included[-2] if len(included) > 1 else True
            included[-1] = parent and not included[-1]
            continue
        if stripped.startswith("#endif"):
            if len(included) > 1:
                included.pop()
            continue
        if included[-1] and any(needle in line for needle in NEEDLES):
            hits.append((number, line.rstrip()))
    return hits


def release_condition(condition: str) -> bool:
    compact = condition.replace(" ", "")
    if compact == "DEBUG":
        return False
    if compact in {"!DEBUG", "!DEBUG"}:
        return True
    # Unknown conditions can be true in a Release build, so keep the line.
    return True


def scan(root: Path) -> int:
    failures = 0
    for path in root.rglob("*.swift"):
        if any(part in SKIP_PARTS for part in path.parts):
            continue
        if "Packages" not in path.parts and "Apps" not in path.parts:
            continue
        hits = release_includes(path.read_text(encoding="utf-8").splitlines())
        for number, text in hits:
            print(f"{path}:{number}: Release source contains a mock-server string: {text}", file=sys.stderr)
            failures += 1
    return failures


def self_test() -> int:
    bad = release_includes(['let name = "MockAPIClient"\n'])
    good = release_includes(["#if DEBUG\n", 'let name = "MockAPIClient"\n', "#endif\n", 'let flag = "-uitest-reset"\n'])
    # The flag line is outside DEBUG, so it must be reported. The type line must not.
    if not bad or any("MockAPIClient" in text for _, text in good if "uitest-" not in text):
        print("debug-string self-test failed", file=sys.stderr)
        return 1
    if not any("uitest-" in text for _, text in good):
        print("debug-string self-test did not flag a Release literal", file=sys.stderr)
        return 1
    print("debug-string self-test passed")
    return 0


def main() -> int:
    if "--self-test" in sys.argv:
        return self_test()
    root = Path(__file__).resolve().parents[1]
    failures = scan(root)
    if failures:
        print(f"debug-string check failed with {failures} hit(s)", file=sys.stderr)
        return 1
    print("debug-string check passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
