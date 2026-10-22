#!/usr/bin/env python3
"""Fail the lint job on logging calls, legacy auth headers, and ATS exceptions.

SwiftLint custom rules do not run on the Linux lint job (they need SourceKit).
This script is the check that does run there.

`print(`, `debugPrint(`, `dump(`, and `NSLog(` are calls only outside comments
and string literals. A line may opt out with `// allow-print: reason`.
Legacy header names are ignored in comments and under `Tests/`, and are still
reported inside string literals, because that is how the header is set.
`NSAllowsArbitraryLoads` is forbidden in every plist.
"""

from __future__ import annotations

import re
import sys
import tempfile
from pathlib import Path

CALL_RE = re.compile(r"\b(?:print|debugPrint|dump|NSLog)\s*\(")
HEADER_RE = re.compile(r"X-Emby-Token|X-MediaBrowser-Token|X-Emby-Authorization")
ALLOW_RE = re.compile(r"//\s*allow-print:\s+\S")
SKIP_PARTS = {".git", ".build", "checkouts"}


def classify(source: str) -> str:
    """Return a same-length mask: c code, m comment, s string."""
    mask = ["c"] * len(source)
    i = 0
    n = len(source)

    def fill(start: int, end: int, kind: str) -> None:
        for index in range(start, end):
            if source[index] != "\n":
                mask[index] = kind

    while i < n:
        if source.startswith("/*", i):
            depth = 1
            start = i
            i += 2
            while i < n and depth:
                if source.startswith("/*", i):
                    depth += 1
                    i += 2
                    continue
                if source.startswith("*/", i):
                    depth -= 1
                    i += 2
                    continue
                i += 1
            fill(start, i, "m")
            continue
        if source.startswith("//", i):
            start = i
            while i < n and source[i] != "\n":
                i += 1
            fill(start, i, "m")
            continue
        opener = opening_string(source, i)
        if opener is not None:
            opener_len, closer = opener
            start = i
            i += opener_len
            while i < n and not source.startswith(closer, i):
                if closer == '"' and source[i] == "\\":
                    i += 2
                    continue
                if source[i] == "\n" and closer == '"':
                    break
                i += 1
            if source.startswith(closer, i):
                i += len(closer)
            fill(start, min(i, n), "s")
            continue
        i += 1
    return "".join(mask)


def opening_string(source: str, index: int) -> tuple[int, str] | None:
    hashes = 0
    while index + hashes < len(source) and source[index + hashes] == "#":
        hashes += 1
    quote_at = index + hashes
    if quote_at >= len(source) or source[quote_at] != '"':
        return None
    if source.startswith('"""', quote_at):
        quote = '"""'
    else:
        quote = '"'
    return hashes + len(quote), quote + ("#" * hashes)


def allows_print(line: str, line_mask: str) -> bool:
    match = ALLOW_RE.search(line)
    if match is None or match.start() >= len(line_mask):
        return False
    return line_mask[match.start()] == "m"


def swift_hits(text: str) -> list[tuple[int, str]]:
    mask = classify(text)
    hits: list[tuple[int, str]] = []
    offset = 0
    for number, line in enumerate(text.splitlines(), start=1):
        line_mask = mask[offset : offset + len(line)]
        offset += len(line) + 1
        code = "".join(char if kind == "c" else " " for char, kind in zip(line, line_mask))
        readable = "".join(char if kind != "m" else " " for char, kind in zip(line, line_mask))
        if not allows_print(line, line_mask):
            for match in CALL_RE.finditer(code):
                hits.append((number, f"forbidden call {match.group(0)}"))
        for match in HEADER_RE.finditer(readable):
            hits.append((number, f"legacy auth header {match.group(0)}"))
    return hits


def plist_hits(text: str) -> list[tuple[int, str]]:
    hits: list[tuple[int, str]] = []
    for number, line in enumerate(text.splitlines(), start=1):
        if "NSAllowsArbitraryLoads" in line:
            hits.append((number, "NSAllowsArbitraryLoads is not allowed"))
    return hits


def skip_swift(path: Path) -> bool:
    return "Tests" in path.parts or any(part in SKIP_PARTS for part in path.parts)


def skip_plist(path: Path) -> bool:
    return any(part in SKIP_PARTS for part in path.parts)


def scan(root: Path) -> list[str]:
    findings: list[str] = []
    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        if path.suffix == ".swift" and not skip_swift(path):
            text = path.read_text(encoding="utf-8", errors="replace")
            for number, message in swift_hits(text):
                findings.append(f"{path}:{number}: {message}")
        elif path.suffix == ".plist" and not skip_plist(path):
            text = path.read_text(encoding="utf-8", errors="replace")
            for number, message in plist_hits(text):
                findings.append(f"{path}:{number}: {message}")
    return findings


def self_test() -> int:
    calls = "func bad() {\n    print(1)\n    debugPrint(1)\n    dump(1)\n    NSLog(\"no\")\n}\n"
    headers = (
        'let token = "X-Emby-Token"\n'
        'let media = "X-MediaBrowser-Token"\n'
        'let auth = "X-Emby-Authorization"\n'
    )
    quiet = (
        "// print( debugPrint( dump( NSLog( X-Emby-Token X-MediaBrowser-Token X-Emby-Authorization\n"
        "/* print( X-Emby-Token */\n"
        'let sample = "print( debugPrint( dump( NSLog("\n'
        'let raw = #"print("#\n'
        "print(1) // allow-print: startup probe\n"
    )
    tests = calls + headers
    plist = "<plist><dict><key>NSAllowsArbitraryLoads</key><true/></dict></plist>\n"
    clean_plist = "<plist><dict><key>NSAllowsLocalNetworking</key><true/></dict></plist>\n"
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        source = root / "Sources"
        source.mkdir()
        (source / "Calls.swift").write_text(calls, encoding="utf-8")
        (source / "Headers.swift").write_text(headers, encoding="utf-8")
        (source / "Quiet.swift").write_text(quiet, encoding="utf-8")
        nested = root / "Packages" / "GlassfinCore" / "Tests"
        nested.mkdir(parents=True)
        (nested / "Ignored.swift").write_text(tests, encoding="utf-8")
        (root / "Info.plist").write_text(plist, encoding="utf-8")
        (source / "Clean.plist").write_text(clean_plist, encoding="utf-8")
        findings = scan(root)
    expected = (
        ("Calls.swift", "print("),
        ("Calls.swift", "debugPrint("),
        ("Calls.swift", "dump("),
        ("Calls.swift", "NSLog("),
        ("Headers.swift", "X-Emby-Token"),
        ("Headers.swift", "X-MediaBrowser-Token"),
        ("Headers.swift", "X-Emby-Authorization"),
        ("Info.plist", "NSAllowsArbitraryLoads"),
    )
    failed = False
    for name, token in expected:
        if not any(name in hit and token in hit for hit in findings):
            print(f"forbidden-call self-test missed {token} in {name}", file=sys.stderr)
            failed = True
    for hit in findings:
        if "Quiet.swift" in hit or "/Tests/" in hit or "Clean.plist" in hit or "Ignored.swift" in hit:
            print(f"forbidden-call self-test counted an ignored line: {hit}", file=sys.stderr)
            failed = True
    if failed:
        return 1
    print("forbidden-call self-test passed")
    return 0


def main() -> int:
    if "--self-test" in sys.argv:
        return self_test()
    root = Path(__file__).resolve().parents[1]
    findings = scan(root)
    if findings:
        for hit in findings:
            print(hit, file=sys.stderr)
        print(f"forbidden-call check failed with {len(findings)} hit(s)", file=sys.stderr)
        return 1
    print("forbidden-call check passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
