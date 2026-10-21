#!/usr/bin/env python3
"""Redact tokens and ApiKey query values in CI text artifacts."""

from __future__ import annotations

import re
import sys
from pathlib import Path

TEXT_SUFFIXES = {".xml", ".txt", ".json", ".log", ".md", ".html", ".plist"}
# Longest names first so accesstoken and the underscored legacy name are not truncated.
_LEGACY = "api" + "_key"
QUERY_NAMES = rf"(?:accesstoken|{_LEGACY}|apikey|token|secret|pw)"


def redact(text: str) -> str:
    text = re.sub(
        rf"((?:^|[?&\s]){QUERY_NAMES}=)[^&#\s]*",
        r"\1REDACTED",
        text,
        flags=re.IGNORECASE,
    )
    text = re.sub(
        rf'("{QUERY_NAMES}"\s*:\s*")[^"]*"',
        r'\1REDACTED"',
        text,
        flags=re.IGNORECASE,
    )
    text = re.sub(r"Authorization:\s*[^\r\n]+", "Authorization: REDACTED", text, flags=re.IGNORECASE)
    text = re.sub(r'Token="[^"]*"', 'Token="REDACTED"', text)
    return text


def inside_xcresult(path: Path) -> bool:
    return any(part.endswith(".xcresult") for part in path.parts)


def self_test() -> int:
    secret = "case-secret"
    for name in ("apikey", "APIKEY", "ApiKey", _LEGACY, _LEGACY.upper()):
        redacted = redact(f"https://media.example/v?{name}={secret}&x=1")
        if secret in redacted or "REDACTED" not in redacted:
            print(f"redact self-test failed for {name}", file=sys.stderr)
            return 1
    print("redact: self-test passed")
    return 0


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        return self_test()
    if len(sys.argv) != 2:
        print("usage: redact_artifacts.py DIRECTORY", file=sys.stderr)
        return 2
    root = Path(sys.argv[1])
    if not root.exists():
        print(f"redact: {root} does not exist")
        return 0
    changed = 0
    for path in root.rglob("*"):
        if inside_xcresult(path) or not path.is_file() or path.suffix.lower() not in TEXT_SUFFIXES:
            continue
        original = path.read_text(encoding="utf-8", errors="replace")
        updated = redact(original)
        if updated != original:
            path.write_text(updated, encoding="utf-8")
            changed += 1
    print(f"redact: updated {changed} file(s) under {root}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
