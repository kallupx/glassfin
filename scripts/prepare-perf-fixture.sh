#!/usr/bin/env bash
# CC0 synthetic media: short native benchmark by default, optional longer LAN fixture.
# Usage: scripts/prepare-perf-fixture.sh [OUTPUT_MP4 [DURATION_SECONDS]]
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
perf_fixture_path="${1:-$root/Tests/Media/Generated/PerfFixture.mp4}"
perf_fixture_duration="${2:-12}"
if [[ $# -gt 2 || ! "$perf_fixture_duration" =~ ^[1-9][0-9]*$ ]]; then
  echo "Usage: scripts/prepare-perf-fixture.sh [OUTPUT_MP4 [DURATION_SECONDS]]" >&2
  exit 2
fi
mkdir -p "$(dirname "$perf_fixture_path")"
ffmpeg -y -hide_banner -loglevel error \
  -f lavfi -i 'testsrc=size=320x180:rate=30' \
  -t "$perf_fixture_duration" -an -c:v libx264 -preset ultrafast -pix_fmt yuv420p \
  -threads 1 -g 30 -map_metadata -1 -movflags +faststart \
  "$perf_fixture_path"
