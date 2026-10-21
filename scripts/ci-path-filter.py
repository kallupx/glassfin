#!/usr/bin/env python3
"""Write GitHub Actions outputs for the macOS path filters."""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

MACOS_PREFIXES = (
    "Packages/",
    "Apps/",
    "Tests/",
    "project.yml",
    ".github/workflows/",
)


def changed_files() -> list[str]:
    event = os.environ.get("GITHUB_EVENT_NAME", "")
    if event == "workflow_dispatch":
        return ["Packages/GlassfinCore/Package.swift"]
    if event == "pull_request":
        base = os.environ["PR_BASE_SHA"]
    else:
        base = os.environ.get("PUSH_BEFORE", "")
        if not base or set(base) == {"0"}:
            base = "HEAD^"
    output = subprocess.check_output(["git", "diff", "--name-only", base, "HEAD"], text=True)
    return [line for line in output.splitlines() if line]


def matches(path: str, prefix: str) -> bool:
    return path == prefix or path.startswith(prefix)


def main() -> None:
    files = changed_files()
    macos = any(matches(path, prefix) for path in files for prefix in MACOS_PREFIXES)
    macos = macos or any(path.endswith("Package.resolved") for path in files)
    ios = any(matches(path, "Apps/iOS/") or matches(path, "Packages/") for path in files)
    if os.environ.get("GITHUB_EVENT_NAME") == "workflow_dispatch":
        macos = True
        ios = True
    output = os.environ.get("GITHUB_OUTPUT")
    lines = f"macos={'true' if macos else 'false'}\nios={'true' if ios else 'false'}\n"
    if output:
        Path(output).open("a", encoding="utf-8").write(lines)
    else:
        print(lines, end="")


if __name__ == "__main__":
    main()
