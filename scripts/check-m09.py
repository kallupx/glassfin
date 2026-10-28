#!/usr/bin/env python3
"""M09 source regressions: T09-25/T09-27/T09-54/T09-65/T09-68 and canonical ID coverage."""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    errors = []
    # T09-65/T09-68: all app and package image paths must avoid full-bitmap decoding.
    sources = list((ROOT / "Apps").rglob("*.swift"))
    sources += list((ROOT / "Packages/GlassfinCore/Sources").rglob("*.swift"))
    forbidden = re.compile(r"\bAsyncImage\b|\bUIImage\s*\(\s*data\s*:|\bCGImageSourceCreateImageAtIndex\b")
    for path in sources:
        if forbidden.search(path.read_text()):
            errors.append(f"{path.relative_to(ROOT)}: forbidden image API (T09-65/T09-68)")

    # T09-27: query text must never be interpolated into a search endpoint path.
    search_paths = [
        "Packages/GlassfinCore/Sources/CoreServices/SearchBackend.swift",
        "Packages/GlassfinCore/Sources/CoreNetworking/ContentSecurity.swift",
        "Packages/GlassfinCore/Sources/CoreAPI/SearchQueryClient.swift",
    ]
    for name in search_paths:
        text = (ROOT / name).read_text()
        if re.search(r'path:\s*"[^"\n]*\\\([^)]*(?:term|query)', text, re.I):
            errors.append(f"{name}: query interpolation into a path (T09-27)")

    # T09-25: keep the production default consistent with ADR-M09-1.
    factory = (ROOT / "Packages/GlassfinCore/Sources/CoreState/SearchFeature.swift").read_text()
    adr = (ROOT / "docs/ADR-M09-1.md").read_text()
    if "backend ?? ItemsSearchBackend(client:" not in factory or "Use `ItemsSearchBackend` by default" not in adr:
        errors.append("Search default and ADR-M09-1 require review together (T09-25)")

    # T09-54: the local-only history store must not acquire cloud, preference or network dependencies.
    store = (ROOT / "Packages/GlassfinCore/Sources/CoreState/RecentSearchStore.swift").read_text()
    if re.search(r"\b(?:CloudKit|NSUbiquitousKeyValueStore|UserDefaults|URLSession|SecureStore)\b", store):
        errors.append("RecentSearchStore has a forbidden persistence/network dependency (T09-54)")

    plan = (ROOT / "spec/TESTPLAN-M09.md").read_text()
    ids = set(re.findall(r"\| (T09-\d+) \|", plan))
    mapping = (ROOT / "docs/M09-TEST-MAPPING.md").read_text()
    mapped = set(re.findall(r"\| (T09-\d+) \|", mapping))
    if ids != mapped:
        errors.append("Canonical plan and coverage mapping must contain exactly the same IDs")
    for root in (ROOT / "Packages/GlassfinCore/Tests", ROOT / "Apps/Shared"):
        for path in root.rglob("*.swift"):
            text = path.read_text()
            for match in re.finditer(r"func testT09_(\d+)_", text):
                canonical = f"T09-{int(match.group(1)):02d}"
                if canonical not in ids:
                    errors.append(f"{path.relative_to(ROOT)}: ID outside the canonical plan: {canonical}")
                before = text[max(0, match.start() - 300):match.start()]
                if canonical not in before:
                    errors.append(f"{path.relative_to(ROOT)}: missing {canonical} test comment")

    for error in errors:
        print(f"check-m09: {error}", file=sys.stderr)
    if errors:
        return 1
    print("check-m09: passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
