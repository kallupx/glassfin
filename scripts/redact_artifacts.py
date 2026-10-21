#!/usr/bin/env python3
"""Redact tokens and ApiKey query values in CI text artifacts."""

from __future__ import annotations

import re
import sys
from pathlib import Path

TEXT_SUFFIXES = {".xml", ".txt", ".json", ".log", ".md", ".html", ".plist"}
KEYS = ("ApiKey", "api_key", "Token", "secret", "Pw", "AccessToken")


def redact(text: str) -> str:
    for key in KEYS:
        text = re.sub(
            rf"((?:^|[?&\s]){re.escape(key)}=)[^&#\s]*",
            r"\1REDACTED",
            text,
        )
        text = re.sub(
            rf'("{re.escape(key)}"\s*:\s*")[^"]*"',
            r'\1REDACTED"',
            text,
        )
    text = re.sub(r"Authorization:\s*[^\r\n]+", "Authorization: REDACTED", text, flags=re.IGNORECASE)
    text = re.sub(r'Token="[^"]*"', 'Token="REDACTED"', text)
    return text


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: redact_artifacts.py DIRECTORY", file=sys.stderr)
        return 2
    root = Path(sys.argv[1])
    if not root.exists():
        print(f"redact: {root} does not exist")
        return 0
    changed = 0
    for path in root.rglob("*"):
        if not path.is_file() or path.suffix.lower() not in TEXT_SUFFIXES:
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
