#!/usr/bin/env python3
"""Turn an xcresult into JUnit XML, coverage JSON, failed-test logs, and screenshots.

xcresult bundles do not open on Linux. These files are the review surface.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import xml.etree.ElementTree as ET
from pathlib import Path


def run(command: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, text=True, capture_output=True, check=False)


def load_tests(xcresult: Path) -> dict:
    modern = run(
        ["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", str(xcresult), "--format", "json"]
    )
    if modern.returncode == 0 and modern.stdout.strip():
        return json.loads(modern.stdout)
    legacy = run(["xcrun", "xcresulttool", "get", "--format", "json", "--path", str(xcresult)])
    if legacy.returncode == 0 and legacy.stdout.strip():
        return json.loads(legacy.stdout)
    return {"rawError": modern.stderr or legacy.stderr}


def collect_cases(node, cases: list[dict]) -> None:
    if isinstance(node, dict):
        name = node.get("name") or node.get("identifier")
        status = node.get("result") or node.get("testStatus") or node.get("status")
        if isinstance(name, str) and isinstance(status, str) and status.lower() in {
            "passed",
            "failed",
            "skipped",
            "success",
            "failure",
        }:
            message = node.get("message") or node.get("failureMessage") or ""
            if not message:
                for key in ("failures", "failureSummaries"):
                    if node.get(key):
                        message = json.dumps(node[key])
                        break
            cases.append({"name": name, "status": status.lower(), "message": str(message)})
        for value in node.values():
            collect_cases(value, cases)
    elif isinstance(node, list):
        for item in node:
            collect_cases(item, cases)


def write_junit(cases: list[dict], destination: Path) -> None:
    suite = ET.Element("testsuite", name="Glassfin", tests=str(len(cases)))
    failures = 0
    for case in cases:
        item = ET.SubElement(suite, "testcase", classname="Glassfin", name=case["name"])
        if case["status"] in {"failed", "failure"}:
            failures += 1
            failure = ET.SubElement(item, "failure", message=case["message"][:500])
            failure.text = case["message"]
        elif case["status"] == "skipped":
            ET.SubElement(item, "skipped")
    suite.set("failures", str(failures))
    destination.write_text(ET.tostring(suite, encoding="unicode"), encoding="utf-8")


def export(xcresult: Path, output: Path) -> None:
    output.mkdir(parents=True, exist_ok=True)
    payload = load_tests(xcresult)
    (output / "xcresult-tests.json").write_text(json.dumps(payload, indent=2), encoding="utf-8")
    cases: list[dict] = []
    collect_cases(payload, cases)
    # The recursive walk also records parent nodes. Keep the longest names.
    unique = {case["name"]: case for case in cases}
    write_junit(list(unique.values()), output / "junit.xml")
    failed = [case for case in unique.values() if case["status"] in {"failed", "failure"}]
    lines = [f"{case['name']}: {case['message']}" for case in failed] or ["no failed tests"]
    (output / "failed-tests.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")

    coverage = run(["xcrun", "xccov", "view", "--report", "--json", str(xcresult)])
    coverage_path = output / "coverage.json"
    if coverage.returncode == 0 and coverage.stdout.strip():
        coverage_path.write_text(coverage.stdout, encoding="utf-8")
    else:
        coverage_path.write_text(
            json.dumps({"error": coverage.stderr or "xccov produced no report"}),
            encoding="utf-8",
        )

    screenshots = output / "screenshots"
    screenshots.mkdir(exist_ok=True)
    run(
        [
            "xcrun",
            "xcresulttool",
            "export",
            "attachments",
            "--path",
            str(xcresult),
            "--output-path",
            str(screenshots),
        ]
    )
    legacy_dir = screenshots / "legacy"
    legacy_dir.mkdir(exist_ok=True)
    run(
        [
            "xcrun",
            "xcresulttool",
            "export",
            "--type",
            "directory",
            "--path",
            str(xcresult),
            "--output-path",
            str(legacy_dir),
        ]
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--xcresult", action="append", default=[], type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    if not args.xcresult:
        print("export: no xcresult paths given")
        return 0
    for index, path in enumerate(args.xcresult):
        if not path.exists():
            print(f"export: missing {path}")
            continue
        destination = args.output if len(args.xcresult) == 1 else args.output / f"bundle-{index}"
        export(path, destination)
        print(f"export: wrote {destination}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
