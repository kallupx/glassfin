#!/usr/bin/env python3
"""Require every shared UI test class in exactly one tvOS CI shard."""

from __future__ import annotations

import argparse
import copy
import json
import re
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "scripts/ci/tvos-ui-shards.json"


def discover_classes(directory: Path) -> set[str]:
    parents = {}
    for path in directory.rglob("*.swift"):
        # Ignore commented-out declarations and class-like text in string literals.
        text = re.sub(
            r'//[^\n]*|/\*.*?\*/|""".*?"""|"(?:\\.|[^"\\])*"',
            "",
            path.read_text(encoding="utf-8"),
            flags=re.DOTALL,
        )
        for match in re.finditer(r"\bclass\s+(\w+)\s*:\s*([^\{]+)\{", text):
            parents[match[1]] = re.findall(r"\b\w+\b", match[2])
    tests = {"XCTestCase"}
    while True:
        found = {name for name, bases in parents.items() if tests.intersection(bases)}
        if found <= tests:
            return tests - {"XCTestCase"}
        tests.update(found)


def check(shards: dict, classes: set[str]) -> list[str]:
    errors = []
    if not isinstance(shards, dict) or not 2 <= len(shards) <= 3:
        return ["the manifest must contain two or three shards"]
    if "1" not in shards:
        errors.append("shard 1 must run the Release, package and hosted unit-test checks")
    for shard, names in shards.items():
        if not re.fullmatch(r"[1-3]", shard):
            errors.append(f"invalid shard ID: {shard!r}")
        if not isinstance(names, list) or not names or any(
            not isinstance(name, str) or not re.fullmatch(r"[A-Za-z_]\w*", name)
            for name in names
        ):
            errors.append(f"shard {shard} must contain a nonempty list of class names")
    if errors:
        return errors
    assigned = Counter(name for names in shards.values() for name in names)
    if not classes:
        errors.append("no XCTestCase classes found in Apps/Shared/UITests")
    for name in sorted(classes - assigned.keys()):
        errors.append(f"unassigned UI test class: {name}")
    for name in sorted(assigned.keys() - classes):
        errors.append(f"unknown UI test class: {name}")
    for name, count in sorted(assigned.items()):
        if count != 1:
            errors.append(f"UI test class assigned {count} times: {name}")
    return errors


def self_test(shards: dict, classes: set[str]) -> None:
    name = shards["1"][0]
    missing = copy.deepcopy(shards)
    missing["1"].remove(name)
    duplicate = copy.deepcopy(shards)
    duplicate["2"].append(name)
    unknown = copy.deepcopy(shards)
    unknown["1"].append("RemovedUITests")
    empty = copy.deepcopy(shards)
    empty["1"] = []
    cases = [
        (shards, classes | {"NewUITests"}, "unassigned UI test class: NewUITests"),
        (missing, classes, f"unassigned UI test class: {name}"),
        (duplicate, classes, f"UI test class assigned 2 times: {name}"),
        (unknown, classes, "unknown UI test class: RemovedUITests"),
        (empty, classes, "nonempty list"),
        (shards, set(), "no XCTestCase classes found"),
    ]
    for fixture, discovered, expected in cases:
        if not any(expected in error for error in check(fixture, discovered)):
            raise ValueError(f"self-test did not reject {expected}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--matrix", action="store_true", help="print the validated Actions matrix")
    mode.add_argument("--shard", help="print xcodebuild -only-testing arguments for a shard")
    mode.add_argument("--self-test", action="store_true", help="exercise guard failure cases")
    args = parser.parse_args()
    try:
        shards = json.loads(MANIFEST.read_text(encoding="utf-8"))
        classes = discover_classes(ROOT / "Apps/Shared/UITests")
        errors = check(shards, classes)
        if errors:
            raise ValueError("\n".join(errors))
        if args.matrix:
            print(json.dumps({"shard": list(shards)}))
        elif args.shard:
            if args.shard not in shards:
                raise ValueError(f"unknown shard: {args.shard}")
            if args.shard == "1":
                print("-only-testing:Glassfin-tvOSUnitTests")
            for name in shards[args.shard]:
                print(f"-only-testing:Glassfin-tvOSUITests/{name}")
        elif args.self_test:
            self_test(shards, classes)
            print("tvOS UI shards self-test passed (6 rejection cases)")
        else:
            print(f"tvOS UI shards check passed: {len(classes)} classes in {len(shards)} shards")
    except (OSError, ValueError) as error:
        print(f"tvOS UI shards: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
