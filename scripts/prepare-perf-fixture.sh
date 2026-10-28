#!/usr/bin/env bash
# A small CC0 synthetic fixture for native playback benchmarks. Never contacts a server.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$root/Tests/Media/Generated"
ffmpeg -y -hide_banner -loglevel error \
  -f lavfi -i 'testsrc=size=320x180:rate=30' \
  -t 12 -an -c:v libx264 -preset ultrafast -pix_fmt yuv420p \
  -threads 1 -g 30 -map_metadata -1 -movflags +faststart \
  "$root/Tests/Media/Generated/PerfFixture.mp4"
