#!/usr/bin/env python3
"""T09-21/T09-22: deterministic 5,000-item library, local NFOs and image tags.

Media is hard-linked to one generated dummy clip. Nothing is downloaded. The fixture
contains 2,000 movies (including an umlaut name), 1,000 series and 2,000 episodes.
"""
from __future__ import annotations

import argparse
import base64
import json
import os
from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parents[1]
POSTER = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aD1sAAAAASUVORK5CYII="
)


def link(source: Path, target: Path) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    os.link(source, target)


def nfo(path: Path, kind: str, title: str, extra: str = "") -> None:
    path.write_text(
        f"<{kind}><title>{escape(title)}</title><year>2024</year>{extra}</{kind}>", encoding="utf-8"
    )


def seed(media: Path, sample: Path, manifest: dict) -> None:
    names = [f"Glassfin Bench Movie {index:04d} (2024)" for index in range(manifest["regularMovies"])]
    for name in names + manifest["extraMovies"]:
        folder = media / "movies" / name
        link(sample, folder / (name + ".mp4"))
        nfo(folder / "movie.nfo", "movie", name)
        (folder / "poster.png").write_bytes(POSTER)
    for index in range(manifest["series"]):
        name = f"Glassfin Bench Series {index:04d}"
        folder = media / "series" / name
        folder.mkdir(parents=True)
        nfo(folder / "tvshow.nfo", "tvshow", name)
        (folder / "poster.png").write_bytes(POSTER)
        for episode in range(1, manifest["episodesPerSeries"] + 1):
            stem = f"{name} S01E{episode:02d}"
            season = folder / "Season 01"
            link(sample, season / (stem + ".mp4"))
            nfo(
                season / (stem + ".nfo"), "episodedetails", f"Glassfin Bench Episode {index:04d}-{episode}",
                f"<season>1</season><episode>{episode}</episode>",
            )
            (season / (stem + "-thumb.png")).write_bytes(POSTER)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--media", type=Path, required=True)
    parser.add_argument("--sample", type=Path, required=True)
    args = parser.parse_args()
    manifest = json.loads((ROOT / "Tests/Fixtures/search-seed.json").read_text(encoding="utf-8"))
    seed(args.media, args.sample, manifest)


if __name__ == "__main__":
    main()
