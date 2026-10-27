#!/usr/bin/env python3
"""T07-78/T07-80: prevent unbounded image loading and full-bitmap decoding."""

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
FORBIDDEN = (
    (r"\bAsyncImage\b", "image requests must use the bounded authenticated pipeline"),
    (r"\b(?:UI|NS)Image\s*\(\s*data\s*:", "encoded bytes must be downsampled with ImageIO"),
    (r"\bCGImageSourceCreateImageAtIndex\s*\(", "full-bitmap decoding is forbidden"),
)


def violations(text: str) -> list[str]:
    return [reason for pattern, reason in FORBIDDEN if re.search(pattern, text)]


def main() -> int:
    paths = set((ROOT / "Apps").rglob("*.swift"))
    paths.update((ROOT / "Packages/GlassfinCore/Sources").rglob("*.swift"))
    errors = []
    for path in sorted(paths):
        errors.extend(f"{path.relative_to(ROOT)}: {reason}" for reason in violations(path.read_text()))
    if errors:
        for error in errors:
            print(f"check-image-pipeline: {error}", file=sys.stderr)
        return 1
    print("check-image-pipeline: passed (T07-78/T07-80)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
