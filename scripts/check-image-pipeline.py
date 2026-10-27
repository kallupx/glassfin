#!/usr/bin/env python3
"""T06-81: forbid full bitmap decoding and framework networking in the image pipeline."""

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
FORBIDDEN = (
    (re.compile(r"\bAsyncImage\b"), "images must use the authenticated, bounded pipeline"),
    (re.compile(r"\bUIImage\s*\(\s*data\s*:", re.MULTILINE), "full bitmap decoding is forbidden"),
    (re.compile(r"\bCGImageSourceCreateImageAtIndex\s*\("), "use ImageIO thumbnail decoding"),
)


def violations(text: str) -> list[str]:
    return [message for pattern, message in FORBIDDEN if pattern.search(text)]


def main() -> int:
    if "--self-test" in sys.argv:
        assert violations("AsyncImage(url: resource)")
        assert violations("Image(uiImage: UIImage(\n data : bytes)!)")
        assert violations("CGImageSourceCreateImageAtIndex(source, 0, nil)")
        assert not violations("CGImageSourceCreateThumbnailAtIndex(source, 0, options)")
        print("check-image-pipeline: self-test passed (T06-81)")
        return 0
    paths = set((ROOT / "Apps").rglob("*.swift"))
    sources = ROOT / "Packages/GlassfinCore/Sources"
    paths.update(sources.rglob("*.swift"))
    errors = [f"{path.relative_to(ROOT)}: {message}" for path in sorted(paths)
              for message in violations(path.read_text(encoding="utf-8"))]
    for error in errors:
        print(f"check-image-pipeline: {error}", file=sys.stderr)
    if errors:
        return 1
    print("check-image-pipeline: passed (T06-81)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
