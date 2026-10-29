#!/usr/bin/env python3
"""Export only allowlisted AVPlayer domain/code summaries before simulator cleanup."""

import json
import os
from pathlib import Path
import re
import subprocess

DOMAINS = (
    "AVFoundationErrorDomain", "CoreMediaErrorDomain", "NSURLErrorDomain",
    "NSPOSIXErrorDomain", "NSOSStatusErrorDomain", "NSCocoaErrorDomain",
    "kCFErrorDomainCFNetwork", "kCFErrorDomainOSStatus", "<redacted-domain>",
)
ENTRY = r"(?:" + "|".join(re.escape(domain) for domain in DOMAINS) + r")\(-?\d+\)"
SUMMARY = re.compile(r"AVPlayer failure: (?:item error unavailable|" + ENTRY + r"(?: <- " + ENTRY + r"){0,4})$")


def summaries(text: str) -> list[str]:
    # Discard timestamp, process metadata and every unstructured line. Even a URL or
    # credential appended to a valid summary makes the entire line ineligible.
    found = []
    for line in text.splitlines():
        start = line.find("AVPlayer failure: ")
        if start >= 0 and SUMMARY.fullmatch(line[start:]):
            found.append(line[start:])
    return found


def main() -> None:
    if os.environ.get("CI") != "true":
        raise RuntimeError("playback diagnostics collection runs only in CI")
    root = Path(os.environ["RUNNER_TEMP"]) / (
        f"glassfin-e2e-{os.environ['GITHUB_RUN_ID']}-{os.environ['GITHUB_RUN_ATTEMPT']}")
    lines = []
    available = False
    simulator = root / "simulator.json"
    if simulator.is_file():
        device = json.loads(simulator.read_text())
        try:
            arguments = ["show", "--style", "compact", "--info", "--last", "30m", "--predicate",
                         'subsystem == "org.glassfin.app" AND category == "playback"']
            # Some simulator runtimes cannot read their historical log store. The
            # host store also contains simulator process logs; apply the same strict
            # summary filter to it. Never export command output or stderr verbatim.
            for command in [["xcrun", "simctl", "spawn", device, "log"], ["/usr/bin/log"]]:
                result = subprocess.run(command + arguments, capture_output=True, text=True, timeout=20, check=False)
                if result.returncode == 0:
                    available = True
                    lines = summaries(result.stdout)
                    break
        except (OSError, subprocess.TimeoutExpired):
            pass
    output = Path(__file__).resolve().parents[2] / "artifacts/jellyfin-e2e/playback-diagnostics.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps({"available": available, "lines": lines}) + "\n")


if __name__ == "__main__":
    main()
