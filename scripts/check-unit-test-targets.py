#!/usr/bin/env python3
"""Guard the hosted unit-test targets and scheme entries in project.yml."""

from __future__ import annotations

import argparse
import copy
import json
import re
import sys
from pathlib import Path

EXPECTED_TARGETS = (
    ("Glassfin-tvOSUnitTests", "tvOS", "Glassfin-tvOS"),
    ("Glassfin-iOSUnitTests", "iOS", "Glassfin-iOS"),
)
REQUIRED_SOURCES = ("Apps/Shared/Tests/Logic", "Apps/Shared/Tests/Snapshots")


def parse_project(text: str) -> dict:
    """Read block mappings/lists and single-line scalars, without PyYAML.

    Ignore comments outside quotes. Reject duplicate keys, malformed indentation,
    and unsupported YAML constructs instead of silently overlooking dependencies.
    """
    lines = []
    for number, raw in enumerate(text.splitlines(), 1):
        # Quoted strings can contain #; a plain # starts a comment after whitespace.
        tokens = re.findall(r'"(?:\\.|[^"\\])*"|\'(?:\'\'|[^\'])*\'|#[^\n]*|[^\'"#]+|.', raw)
        clean = ""
        for token in tokens:
            if token.startswith("#") and (not clean or clean[-1].isspace()):
                break
            clean += token
        clean = clean.rstrip()
        if not clean:
            continue
        indent = len(clean) - len(clean.lstrip())
        if "\t" in clean[:indent]:
            raise ValueError(f"line {number}: tabs in indentation")
        value = clean[indent:]
        if value == "-" or value.startswith("- "):
            lines.append((indent, "-", number))
            if value[1:].strip():
                lines.append((indent + 2, value[1:].strip(), number))
        else:
            lines.append((indent, value, number))

    def scalar(value: str) -> str:
        if value.startswith('"'):
            return json.loads(value)
        if value.startswith("'") and value.endswith("'"):
            return value[1:-1].replace("''", "'")
        if value.startswith(("[", "{", "&", "*", "!", "|", ">", "'")):
            raise ValueError(f"unsupported YAML value {value!r}; use block mappings/lists")
        return value

    def block(index: int):
        indent, value, number = lines[index]
        sequence = value == "-"
        if not sequence and not re.search(r":(?:\s|$)", value):
            return scalar(value), index + 1
        result = [] if sequence else {}
        while index < len(lines) and lines[index][0] == indent:
            _, value, number = lines[index]
            if sequence:
                if value != "-":
                    raise ValueError(f"line {number}: expected a list item")
                tail = ""
            else:
                pair = re.split(r":(?:\s|$)", value, maxsplit=1)
                if len(pair) != 2:
                    raise ValueError(f"line {number}: expected a mapping entry")
                key, tail = scalar(pair[0]), pair[1].strip()
                if key in result:
                    raise ValueError(f"line {number}: duplicate key {key}")
            index += 1
            child = scalar(tail) if tail else None
            if index < len(lines) and lines[index][0] > indent:
                if tail:
                    raise ValueError(f"line {number}: unexpected nested content")
                child, index = block(index)
            if sequence:
                result.append(child)
            else:
                result[key] = child
        return result, index

    if not lines:
        return {}
    result, end = block(0)
    if end != len(lines) or lines[0][0] != 0 or not isinstance(result, dict):
        raise ValueError("expected a top-level block mapping with consistent indentation")
    return result


def mapping(value) -> dict:
    return value if isinstance(value, dict) else {}


def entries(value) -> list:
    return value if isinstance(value, list) else []


def check(text: str) -> list[str]:
    try:
        project = parse_project(text)
    except ValueError as error:
        return [f"cannot parse project.yml: {error}"]
    errors = []
    targets = mapping(project.get("targets"))
    schemes = mapping(project.get("schemes"))
    for name, platform, app in EXPECTED_TARGETS:
        target = mapping(targets.get(name))
        if not target:
            errors.append(f"missing target {name}")
        else:
            for key, expected in (("platform", platform), ("type", "bundle.unit-test")):
                if target.get(key) != expected:
                    errors.append(f"{name}: {key} must be {expected}")
            sources = entries(target.get("sources"))
            paths = [mapping(item).get("path") if isinstance(item, dict) else item for item in sources]
            for path in REQUIRED_SOURCES:
                if path not in paths:
                    errors.append(f"{name}: missing source {path}")
            dependencies = [mapping(item) for item in entries(target.get("dependencies"))]
            if not any(item.get("target") == app for item in dependencies):
                errors.append(f"{name}: missing app dependency {app}")
            if any(item.get("package") == "GlassfinCore" for item in dependencies):
                errors.append(f"{name}: forbidden package dependency GlassfinCore (hosted tests must not link it)")
        test = mapping(mapping(schemes.get(app)).get("test"))
        names = [
            mapping(item).get("name") if isinstance(item, dict) else item
            for item in entries(test.get("targets"))
        ]
        if name not in names:
            errors.append(f"scheme {app}: missing test target {name}")
    return errors


def fixture_yaml(value, indent: int = 0) -> str:
    """Serialize fixture copies so self-tests also exercise the text parser."""
    if isinstance(value, dict):
        return "".join(
            " " * indent + json.dumps(key) + ":\n" + fixture_yaml(item, indent + 2)
            for key, item in value.items()
        )
    if isinstance(value, list):
        return "".join(" " * indent + "-\n" + fixture_yaml(item, indent + 2) for item in value)
    return " " * indent + json.dumps(value) + "\n"


def self_test(text: str) -> int:
    failures = []
    errors = check(text)
    if errors:
        print("unit-test targets self-test: current project.yml must pass:\n  " + "\n  ".join(errors), file=sys.stderr)
        return 1
    project = parse_project(text)
    if check(fixture_yaml(project)):
        failures.append("quoted and reindented fixture must pass")
    commented = "\n".join(line + " # ignored comment" for line in text.splitlines() if line.strip())
    if check(commented):
        failures.append("inline comments must pass")
    scalar_lists = copy.deepcopy(project)
    for name, _, app in EXPECTED_TARGETS:
        scalar_lists["targets"][name]["sources"] = list(REQUIRED_SOURCES)
        scalar_lists["schemes"][app]["test"]["targets"] = [name]
    if check(fixture_yaml(scalar_lists)):
        failures.append("scalar source and scheme target lists must pass")

    def reject(label, fixture, expected):
        errors = check(fixture_yaml(fixture))
        if not any(expected in error for error in errors):
            failures.append(f"{label}: expected {expected!r}, got {errors!r}")

    for name, _, app in EXPECTED_TARGETS:
        fixture = copy.deepcopy(project)
        del fixture["targets"][name]
        reject("removed target", fixture, f"missing target {name}")

        fixture = copy.deepcopy(project)
        fixture["targets"][name + "'"] = fixture["targets"].pop(name)
        reject("similar target name", fixture, f"missing target {name}")

        fixture = copy.deepcopy(project)
        test = fixture["schemes"][app]["test"]
        test["targets"] = [item for item in test["targets"] if mapping(item).get("name", item) != name]
        reject("removed scheme entry", fixture, f"scheme {app}: missing test target {name}")

        fixture = copy.deepcopy(project)
        fixture["targets"][name]["dependencies"].append({"package": "GlassfinCore"})
        reject("added package dependency", fixture, f"{name}: forbidden package dependency GlassfinCore")

        for path in REQUIRED_SOURCES:
            fixture = copy.deepcopy(project)
            target = fixture["targets"][name]
            target["sources"] = [item for item in target["sources"] if mapping(item).get("path", item) != path]
            reject("removed source", fixture, f"{name}: missing source {path}")

        for key, wrong in (("platform", "macOS"), ("type", "bundle.ui-testing"), ("dependencies", [])):
            fixture = copy.deepcopy(project)
            fixture["targets"][name][key] = wrong
            expected = f"{name}: missing app dependency {app}" if key == "dependencies" else f"{name}: {key} must be"
            reject(f"incorrect {key}", fixture, expected)

    if failures:
        print("unit-test targets self-test failed:\n  " + "\n  ".join(failures), file=sys.stderr)
        return 1
    print("unit-test targets self-test passed")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true", help="check in-memory regression fixtures")
    args = parser.parse_args()
    path = Path(__file__).resolve().parents[1] / "project.yml"
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as error:
        print(f"unit-test targets: cannot read {path}: {error}", file=sys.stderr)
        return 1
    if args.self_test:
        return self_test(text)
    errors = check(text)
    if errors:
        for error in errors:
            print(f"unit-test targets: {error}", file=sys.stderr)
        return 1
    print("unit-test targets check passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
