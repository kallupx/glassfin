#!/usr/bin/env python3
"""Source checks for the M05 design system.

Rows that are source inspections live here: T05-02, T05-03, T05-04, T05-05,
T05-06, T05-07 (no availability checks and deployment 26), T05-22, T05-34,
T05-42, T05-48, T05-53, T05-54, and T05-55. Behavioral rows have XCTest names.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOTS = (
    ROOT / "Apps/Shared/Sources",
    ROOT / "Apps/tvOS/Sources",
    ROOT / "Apps/iOS/Sources",
    ROOT / "Apps/TopShelf/Sources",
)
FORBIDDEN = (
    (re.compile(r"\.blur\("), ".blur( is not used"),
    (re.compile(r"\.shadow\("), ".shadow( is not used"),
    (re.compile(r"\.border\("), ".border( is not used"),
    (
        re.compile(r"ultraThinMaterial|thinMaterial|regularMaterial|thickMaterial|ultraThickMaterial|barMaterial"),
        "Material styles are not used",
    ),
    (re.compile(r"#available"), "#available is not allowed"),
    (re.compile(r"scrollEdgeEffectStyle"), "scrollEdgeEffectStyle must stay at the system default (T05-34)"),
    (re.compile(r"\bprint\("), "print( is not allowed"),
    (re.compile(r"(?<![A-Za-z])Link\("), "Link( is not allowed"),
    (re.compile(r"(?<![A-Za-z])openURL"), "openURL is not allowed"),
    (re.compile(r"NSAttributedString"), "NSAttributedString is not allowed"),
    (re.compile(r'\bText\("'), 'Text(" is not allowed; use Copy or Text(verbatim:)'),
    (re.compile(r'\bButton\("'), 'Button(" is not allowed; use Copy'),
    (re.compile(r'\bLabel\("'), 'Label(" is not allowed; use Copy'),
    (re.compile(r"\.foregroundStyle\(\.white\)"), "foregroundStyle(.white) is not allowed"),
    (re.compile(r"\.foregroundStyle\(\.black\)"), "foregroundStyle(.black) is not allowed"),
)
ONLY_IN = {
    "glassEffect(": "GlassChrome.swift",
    ".tint(": "GlassChrome.swift",
    ".interactive()": "GlassChrome.swift",
    "buttonStyle(.card)": "GlassChrome.swift",
    "Image(systemName:": "Copy.swift",
    "Color.white": "Tokens.swift",
    "Color.black": "Tokens.swift",
}
IDENTIFIER = re.compile(r'accessibilityIdentifier\(\s*"([^"\\]+)"\s*\)')
IDENTIFIER_SHAPE = re.compile(r"^[a-zA-Z][a-zA-Z0-9]*(\.[a-zA-Z][a-zA-Z0-9]*)+$")
FINNISH = re.compile(r"[äöåÄÖÅ]")
ADR_MARKERS = (
    "Q5-01",
    "Q5-02",
    "Q5-03",
    "Q5-04",
    "Q5-05",
    "Q5-06",
    "Q5-07",
    "Q5-08",
    "Q5-09",
    "Q5-10",
    "Q5-11",
    "Q5-12",
    "T05-47",
    "T05-48",
    "T05-49",
    "T05-50",
    "T05-51",
    "T05-52",
    "Status: open",
)


def fail(message: str) -> None:
    print(f"check-design-system: {message}", file=sys.stderr)


def swift_files(roots: tuple[Path, ...]) -> list[Path]:
    files: list[Path] = []
    for root in roots:
        if root.exists():
            files.extend(sorted(root.rglob("*.swift")))
    return files


def card_style_is_tvos_only(text: str) -> bool:
    marker = "buttonStyle(.card)"
    start = text.find(marker)
    if start < 0:
        return False
    before = text.rfind("#if os(tvOS)", 0, start)
    if before < 0:
        return False
    else_at = text.find("#else", before)
    return else_at != -1 and before < start < else_at


def main() -> int:
    errors: list[str] = []
    sources = swift_files(SOURCE_ROOTS)
    apps = swift_files((ROOT / "Apps",))

    for path in sources:
        text = path.read_text(encoding="utf-8")
        relative = path.relative_to(ROOT)
        for pattern, message in FORBIDDEN:
            if pattern.search(text):
                errors.append(f"{relative}: {message} (T05-03/T05-04/T05-05)")
        for needle, allowed in ONLY_IN.items():
            if needle in text and path.name != allowed:
                errors.append(f"{relative}: {needle} is only allowed in {allowed}")

    banner = (ROOT / "Apps/Shared/Sources/DesignSystem/GlassBanner.swift").read_text(encoding="utf-8")
    if "ownGlassSurface" not in banner:
        errors.append("GlassBanner.swift must call ownGlassSurface (T05-02)")
    if "GlassEffectContainer" in banner or "ContainedGlass" in banner:
        errors.append("GlassBanner.swift must not use a GlassEffectContainer (T05-02)")

    for path in sources:
        if path.name == "GlassBanner.swift":
            continue
        text = path.read_text(encoding="utf-8")
        if "ownGlassSurface" in text and "ContainedGlass" not in text and "GlassEffectContainer" not in text:
            errors.append(f"{path.relative_to(ROOT)}: ownGlassSurface must sit in a container (T05-02)")

    cards = (ROOT / "Apps/Shared/Sources/DesignSystem/Cards.swift").read_text(encoding="utf-8")
    for needle in ("glassEffect", "ownGlassSurface", "GlassEffectContainer"):
        if needle in cards:
            errors.append(f"Cards.swift must not contain {needle} (T05-42)")

    panels = (ROOT / "Apps/Shared/Sources/DesignSystem/Panels.swift").read_text(encoding="utf-8")
    cue_start = panels.find("struct SubtitleCue")
    cue = panels[cue_start:] if cue_start >= 0 else ""
    if "glassEffect" in cue or "ownGlassSurface" in cue or "GlassEffectContainer" in cue:
        errors.append("SubtitleCue must not use glass (T05-42)")

    chrome = (ROOT / "Apps/Shared/Sources/DesignSystem/GlassChrome.swift").read_text(encoding="utf-8")
    if not card_style_is_tvos_only(chrome):
        errors.append("buttonStyle(.card) must stay inside #if os(tvOS) (T05-55)")
    if ".plain" not in chrome:
        errors.append("non-tvOS poster buttons must use a plain style (T05-55)")

    for path in apps:
        text = path.read_text(encoding="utf-8")
        if "AVPlayerViewController" in text:
            errors.append(f"{path.relative_to(ROOT)}: AVPlayerViewController is out of scope (T05-48)")
        if FINNISH.search(text):
            errors.append(f"{path.relative_to(ROOT)}: Finnish letters belong in the String Catalog")
        if path.suffix == ".swift" and "Tests" not in path.parts and "UITests" not in path.parts:
            for match in IDENTIFIER.finditer(text):
                value = match.group(1)
                if not IDENTIFIER_SHAPE.match(value):
                    errors.append(f"{path.relative_to(ROOT)}: identifier {value!r} is not screen.element (T05-22)")

    project = (ROOT / "project.yml").read_text(encoding="utf-8")
    if 'iOS: "26.0"' not in project or 'tvOS: "26.0"' not in project:
        errors.append("deployment target must be 26 (T05-07)")

    shell = (ROOT / "Apps/Shared/Sources/DesignSystem/Shell.swift").read_text(encoding="utf-8")
    for needle in ("role: .search", "tabViewStyle(.sidebarAdaptable)", "tabBarMinimizeBehavior"):
        if needle not in shell:
            errors.append(f"Shell.swift is missing {needle} (T05-54)")

    adr_path = ROOT / "docs/ADR-M05-1.md"
    if not adr_path.exists():
        errors.append("docs/ADR-M05-1.md is missing (T05-53)")
    else:
        adr = adr_path.read_text(encoding="utf-8")
        for marker in ADR_MARKERS:
            if marker not in adr:
                errors.append(f"ADR-M05-1 is missing {marker} (T05-53)")
        if "Status: resolved" in adr:
            errors.append("ADR-M05-1 must stay open until the warning evidence is reviewed (T05-53)")

    if errors:
        for message in errors:
            fail(message)
        return 1
    print("check-design-system: passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
