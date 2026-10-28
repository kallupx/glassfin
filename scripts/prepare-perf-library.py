#!/usr/bin/env python3
"""Seed synthetic LAN measurement media with hard links and offline NFO metadata."""

import argparse
import os
import shutil
import struct
import zlib
from pathlib import Path


def png() -> bytes:
    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))

    width, height = 320, 480
    pixels = (b'\0' + bytes((24, 96, 128)) * width) * height
    return (b'\x89PNG\r\n\x1a\n'
            + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(pixels)) + chunk(b'IEND', b''))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path, help='Dedicated empty fixture directory')
    parser.add_argument('--video', type=Path, required=True, help='Synthetic MP4, never personal media')
    parser.add_argument('--movies', type=int, default=5000)
    parser.add_argument('--series', type=int, default=500)
    args = parser.parse_args()
    if args.movies < 0 or args.series < 0:
        parser.error('Counts must be nonnegative')
    root = args.directory.resolve()
    root.mkdir(parents=True, exist_ok=True)
    if any(root.iterdir()):
        parser.error('Destination must be empty; existing files are never replaced')
    # Copy once onto the destination volume; every media entry then shares those bytes.
    source = root / 'fixture.mp4'
    shutil.copyfile(args.video, source)
    poster = png()
    for index in range(1, args.movies + 1):
        title = f'Perf Movie {index:05d}'
        folder = root / 'movies' / title
        folder.mkdir(parents=True)
        os.link(source, folder / f'{title}.mp4')
        (folder / 'movie.nfo').write_text(f'<movie><title>{title}</title><year>2026</year></movie>\n')
        (folder / 'poster.png').write_bytes(poster)
    for index in range(1, args.series + 1):
        title = f'Perf Series {index:04d}'
        folder = root / 'shows' / title
        season = folder / 'Season 01'
        season.mkdir(parents=True)
        os.link(source, season / f'{title} S01E01.mp4')
        (folder / 'tvshow.nfo').write_text(f'<tvshow><title>{title}</title><year>2026</year></tvshow>\n')
        (folder / 'poster.png').write_bytes(poster)
        (season / f'{title} S01E01.nfo').write_text(
            '<episodedetails><title>Episode 1</title><season>1</season><episode>1</episode></episodedetails>\n')
    print(f'Created {args.movies} movies and {args.series} series with synthetic posters')


if __name__ == '__main__':
    main()
