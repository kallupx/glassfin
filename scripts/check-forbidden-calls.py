#!/usr/bin/env python3
"""Fail the lint job on logging calls, legacy auth headers, and ATS exceptions.

SwiftLint custom rules do not run on the Linux lint job (they need SourceKit).
This script is the check that does run there.

`print(`, `debugPrint(`, `dump(`, and `NSLog(` are calls only outside comments
and string literals. Code inside string interpolation is scanned as code,
including raw strings: `"value \\(dump(x))"` and `#"raw \\#(print(1))"#`
(any number of `#` delimiters, nested parentheses). A line may opt out of the
call check and the public-log check with `// allow-print: reason`.

Those call checks cover shipping code only. Any path component ending in
`Tests` (`Tests`, `UITests`, `GlassfinCoreTests`) is test code and is skipped
for `print` / `debugPrint` / `dump` / `NSLog`. Legacy headers, plist ATS keys,
and `.public` credential lines are not part of that skip: they apply in test
directories too. xcresult bundles are not uploaded from CI; the macOS jobs
upload the redacted text export only.

Legacy header names are matched case-insensitively and are ignored in
comments. They are still reported inside string literals, because that is how
the header is set. `NSAllowsArbitraryLoads` is a substring match, so it also
catches `NSAllowsArbitraryLoadsForMedia` and `NSAllowsArbitraryLoadsInWebContent`.
`NSExceptionAllowsInsecureHTTPLoads` is forbidden in every plist.
`NSExceptionMinimumTLSVersion` followed by `<string>TLSv1.0</string>` or
`<string>TLSv1.1</string>` is forbidden. `TLSv1.2`, `TLSv1.3`, and
`NSAllowsLocalNetworking` are allowed.
A line that contains `.public` and a credential word (`token`, `password`,
`apiKey`, or `secret`, case-insensitive) fails unless that line has an
`// allow-print: reason` comment.

Known limitations: a call split across lines (`print` then `(1)` on the next
line) is not detected, and a function reference (`let f = print`) is not a call.
"""

from __future__ import annotations

import re
import sys
import tempfile
from pathlib import Path

CALL_RE = re.compile(r"\b(?:print|debugPrint|dump|NSLog)\s*\(")
HEADER_RE = re.compile(r"X-Emby-Token|X-MediaBrowser-Token|X-Emby-Authorization", re.IGNORECASE)
ALLOW_RE = re.compile(r"//\s*allow-print:\s+\S")
PUBLIC_RE = re.compile(r"\.public\b")
SENSITIVE_RE = re.compile(r"\b(?:token|password|apikey|secret)\b", re.IGNORECASE)
WEAK_TLS_RE = re.compile(
    r"NSExceptionMinimumTLSVersion\s*</key>\s*<string>\s*(TLSv1\.0|TLSv1\.1)\s*</string>"
)
SKIP_PARTS = {".git", ".build", "checkouts"}


def classify(source: str) -> str:
    """Return a same-length mask: c code, m comment, s string.

    Interpolation expressions are code. The `\\(` introducer and its closing
    parenthesis stay string text.
    """
    mask = ["c"] * len(source)
    n = len(source)
    i = 0
    # Frames: ("code",), ("block", depth), ("line",), ("string", closer, hashes), ("interp", depth).
    stack: list[tuple] = [("code",)]

    def paint(start: int, end: int, kind: str) -> None:
        for index in range(start, min(end, n)):
            if source[index] != "\n":
                mask[index] = kind

    while i < n:
        frame = stack[-1]
        kind = frame[0]
        if kind == "block":
            if source.startswith("/*", i):
                stack[-1] = ("block", frame[1] + 1)
                paint(i, i + 2, "m")
                i += 2
                continue
            if source.startswith("*/", i):
                paint(i, i + 2, "m")
                i += 2
                depth = frame[1] - 1
                if depth == 0:
                    stack.pop()
                else:
                    stack[-1] = ("block", depth)
                continue
            paint(i, i + 1, "m")
            i += 1
            continue
        if kind == "line":
            if source[i] == "\n":
                stack.pop()
                i += 1
                continue
            paint(i, i + 1, "m")
            i += 1
            continue
        if kind == "string":
            closer, hashes = frame[1], frame[2]
            introducer = "\\" + ("#" * hashes) + "("
            if source.startswith(introducer, i):
                paint(i, i + len(introducer), "s")
                i += len(introducer)
                stack.append(("interp", 1))
                continue
            if source.startswith(closer, i):
                paint(i, i + len(closer), "s")
                i += len(closer)
                stack.pop()
                continue
            if hashes == 0 and closer == '"' and source[i] == "\\":
                paint(i, i + 2, "s")
                i += 2
                continue
            if source[i] == "\n" and closer == '"':
                stack.pop()
                i += 1
                continue
            paint(i, i + 1, "s")
            i += 1
            continue
        if kind == "interp":
            if source.startswith("/*", i):
                stack.append(("block", 1))
                paint(i, i + 2, "m")
                i += 2
                continue
            if source.startswith("//", i):
                stack.append(("line",))
                paint(i, i + 2, "m")
                i += 2
                continue
            opener = opening_string(source, i)
            if opener is not None:
                opener_len, string_closer, hashes = opener
                paint(i, i + opener_len, "s")
                i += opener_len
                stack.append(("string", string_closer, hashes))
                continue
            if source[i] == "(":
                stack[-1] = ("interp", frame[1] + 1)
                paint(i, i + 1, "c")
                i += 1
                continue
            if source[i] == ")":
                depth = frame[1] - 1
                i += 1
                if depth == 0:
                    paint(i - 1, i, "s")
                    stack.pop()
                else:
                    paint(i - 1, i, "c")
                    stack[-1] = ("interp", depth)
                continue
            paint(i, i + 1, "c")
            i += 1
            continue
        if source.startswith("/*", i):
            stack.append(("block", 1))
            paint(i, i + 2, "m")
            i += 2
            continue
        if source.startswith("//", i):
            stack.append(("line",))
            paint(i, i + 2, "m")
            i += 2
            continue
        opener = opening_string(source, i)
        if opener is not None:
            opener_len, string_closer, hashes = opener
            paint(i, i + opener_len, "s")
            i += opener_len
            stack.append(("string", string_closer, hashes))
            continue
        i += 1
    return "".join(mask)


def opening_string(source: str, index: int) -> tuple[int, str, int] | None:
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
    return hashes + len(quote), quote + ("#" * hashes), hashes


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
        if len(line_mask) < len(line):
            line_mask = line_mask + ("c" * (len(line) - len(line_mask)))
        code = "".join(char if kind == "c" else " " for char, kind in zip(line, line_mask))
        readable = "".join(char if kind != "m" else " " for char, kind in zip(line, line_mask))
        allowed = allows_print(line, line_mask)
        if not allowed:
            for match in CALL_RE.finditer(code):
                hits.append((number, f"forbidden call {match.group(0)}"))
            if PUBLIC_RE.search(readable):
                for match in SENSITIVE_RE.finditer(readable):
                    hits.append((number, f"public log mentions {match.group(0)}"))
        for match in HEADER_RE.finditer(readable):
            hits.append((number, f"legacy auth header {match.group(0)}"))
    return hits


def plist_hits(text: str) -> list[tuple[int, str]]:
    hits: list[tuple[int, str]] = []
    for number, line in enumerate(text.splitlines(), start=1):
        if "NSAllowsArbitraryLoads" in line or "NSExceptionAllowsInsecureHTTPLoads" in line:
            hits.append((number, line.strip()))
    for match in WEAK_TLS_RE.finditer(text):
        line = text.count("\n", 0, match.start()) + 1
        hits.append((line, f"NSExceptionMinimumTLSVersion {match.group(1)} is not allowed"))
    return hits


def hidden(path: Path) -> bool:
    return any(part in SKIP_PARTS for part in path.parts)


def is_test_code(path: Path) -> bool:
    """True for Tests, UITests, GlassfinCoreTests, and any other *Tests directory."""
    return any(part.endswith("Tests") for part in path.parts)


def scan(root: Path) -> list[str]:
    findings: list[str] = []
    for path in sorted(root.rglob("*")):
        if not path.is_file() or hidden(path):
            continue
        if path.suffix == ".swift":
            text = path.read_text(encoding="utf-8", errors="replace")
            for number, message in swift_hits(text):
                if is_test_code(path) and message.startswith("forbidden call"):
                    continue
                findings.append(f"{path}:{number}: {message}")
        elif path.suffix == ".plist":
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
        'let lower = "x-emby-token"\n'
    )
    quiet = (
        "// print( debugPrint( dump( NSLog( X-Emby-Token X-MediaBrowser-Token X-Emby-Authorization\n"
        "/* print( X-Emby-Token */\n"
        'let sample = "print( debugPrint( dump( NSLog("\n'
        'let raw = #"print("#\n'
        "print(1) // allow-print: startup probe\n"
        "// privacy: .public token password apiKey secret\n"
        'logger.log(privacy: .private, "token")\n'
        'logger.log(privacy: .public, "name")\n'
    )
    interpolated = (
        'let value = "value \\(dump(x))"\n'
        'let nested = "\\(print(foo(1)))"\n'
        'let raw = #"raw \\#(print(1))"#\n'
        'let raw2 = ##"raw \\##(dump(bar(1)))"##\n'
    )
    public_hits = (
        'logger.log(privacy: .public, "token")\n'
        'logger.log(privacy: .public, "Password")\n'
        'logger.log(privacy: .public, "apiKey")\n'
        'logger.log(privacy: .public, "secret")\n'
    )
    allowed = 'logger.log(privacy: .public, "token") // allow-print: redacted sample\n'
    plist = (
        "<plist><dict>\n"
        "<key>NSAllowsArbitraryLoads</key><true/>\n"
        "<key>NSAllowsArbitraryLoadsForMedia</key><true/>\n"
        "<key>NSAllowsArbitraryLoadsInWebContent</key><true/>\n"
        "<key>NSExceptionAllowsInsecureHTTPLoads</key><true/>\n"
        "</dict></plist>\n"
    )
    weak_tls = (
        "<plist><dict>\n"
        "<key>NSExceptionMinimumTLSVersion</key>\n"
        "<string>TLSv1.0</string>\n"
        "<key>NSExceptionMinimumTLSVersion</key><string>TLSv1.1</string>\n"
        "</dict></plist>\n"
    )
    clean_plist = (
        "<plist><dict>\n"
        "<key>NSAllowsLocalNetworking</key><true/>\n"
        "<key>NSExceptionMinimumTLSVersion</key>\n"
        "<string>TLSv1.2</string>\n"
        "<key>NSExceptionMinimumTLSVersion</key>\n"
        "<string>TLSv1.3</string>\n"
        "</dict></plist>\n"
    )
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        source = root / "Sources"
        source.mkdir()
        (source / "Calls.swift").write_text(calls, encoding="utf-8")
        (source / "Headers.swift").write_text(headers, encoding="utf-8")
        (source / "Quiet.swift").write_text(quiet, encoding="utf-8")
        (source / "Interpolated.swift").write_text(interpolated, encoding="utf-8")
        (source / "Public.swift").write_text(public_hits, encoding="utf-8")
        (source / "Allowed.swift").write_text(allowed, encoding="utf-8")
        for relative in (
            "Packages/GlassfinCore/Tests/Calls.swift",
            "Apps/Shared/UITests/Calls.swift",
            "Packages/GlassfinCoreTests/Calls.swift",
        ):
            path = root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(calls, encoding="utf-8")
        still = root / "Packages" / "GlassfinCore" / "Tests" / "Still.swift"
        still.write_text(headers + public_hits, encoding="utf-8")
        uitests_plist = root / "Apps" / "Shared" / "UITests" / "Bad.plist"
        uitests_plist.write_text(plist, encoding="utf-8")
        (root / "Info.plist").write_text(plist, encoding="utf-8")
        (root / "WeakTLS.plist").write_text(weak_tls, encoding="utf-8")
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
        ("Headers.swift", "x-emby-token"),
        ("Interpolated.swift", "dump("),
        ("Interpolated.swift", "print("),
        ("Still.swift", "X-Emby-Token"),
        ("Still.swift", "token"),
        ("UITests/Bad.plist", "NSExceptionAllowsInsecureHTTPLoads"),
        ("Public.swift", "token"),
        ("Public.swift", "Password"),
        ("Public.swift", "apiKey"),
        ("Public.swift", "secret"),
        ("Info.plist", "NSAllowsArbitraryLoads"),
        ("Info.plist", "NSAllowsArbitraryLoadsForMedia"),
        ("Info.plist", "NSAllowsArbitraryLoadsInWebContent"),
        ("Info.plist", "NSExceptionAllowsInsecureHTTPLoads"),
        ("WeakTLS.plist", "TLSv1.0"),
        ("WeakTLS.plist", "TLSv1.1"),
    )
    failed = False
    for name, token in expected:
        if not any(name in hit and token in hit for hit in findings):
            print(f"forbidden-call self-test missed {token} in {name}", file=sys.stderr)
            failed = True
    # The plain NSAllowsArbitraryLoads key must not be the only ATS hit.
    loads_hits = [hit for hit in findings if "Info.plist" in hit and "NSAllowsArbitraryLoads" in hit]
    if len(loads_hits) < 3:
        print("forbidden-call self-test missed an NSAllowsArbitraryLoads variant", file=sys.stderr)
        failed = True
    interpolated_hits = [hit for hit in findings if "Interpolated.swift" in hit]
    if not any("dump(" in hit for hit in interpolated_hits) or not any("print(" in hit for hit in interpolated_hits):
        print("forbidden-call self-test missed a raw or nested interpolation", file=sys.stderr)
        failed = True
    for hit in findings:
        if "forbidden call" in hit and any(part.endswith("Tests") for part in Path(hit.split(":", 1)[0]).parts):
            print(f"forbidden-call self-test counted a call in test code: {hit}", file=sys.stderr)
            failed = True
        if any(name in hit for name in ("Quiet.swift", "Clean.plist", "Allowed.swift")):
            print(f"forbidden-call self-test counted an ignored line: {hit}", file=sys.stderr)
            failed = True
    if failed:
        for hit in findings:
            print(hit, file=sys.stderr)
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
