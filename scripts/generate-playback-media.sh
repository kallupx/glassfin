#!/usr/bin/env bash
# Synthetic lavfi test patterns and sine waves, dedicated to the public domain (CC0).
# Generate locally; these clips must never be committed or uploaded as CI artifacts.
set -euo pipefail
media_dir="${1:?Usage: generate-playback-media.sh MEDIA_DIRECTORY}"
if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "playback-media: ffmpeg is required" >&2
  exit 1
fi
encoders="$(ffmpeg -hide_banner -encoders 2>/dev/null)"
for encoder in libx264 libx265 aac eac3 dca mpeg2video; do
  if [[ ! "$encoders" =~ [[:space:]]${encoder}[[:space:]] ]]; then
    echo "playback-media: ffmpeg encoder '$encoder' is required for the M08a-PoC fixtures" >&2
    exit 1
  fi
done
mkdir -p "$media_dir"

generate() {
  local name="$1"
  shift
  if ! ffmpeg -y -hide_banner -loglevel error \
    -f lavfi -i "testsrc=size=320x240:rate=24" \
    -f lavfi -i "sine=frequency=440:sample_rate=48000" \
    -t 3 -shortest -threads 1 -pix_fmt yuv420p "$@" "$media_dir/$name"; then
    echo "playback-media: failed to encode '$name' (check ffmpeg's encoder support above)" >&2
    exit 1
  fi
}

generate "Test Movie (2024).mp4" -c:v libx264 -c:a aac
generate "Glassfin HEVC EAC3 (2024).mp4" -c:v libx265 -x265-params pools=none:frame-threads=1:log-level=error \
  -tag:v hvc1 -c:a eac3
generate "Glassfin Remux (2024).mkv" -c:v libx264 -c:a aac
generate "Glassfin DTS (2024).mkv" -c:v libx264 -c:a dca -strict -2
generate "Glassfin Unsupported (2024).mkv" -c:v mpeg2video -c:a aac
echo "playback-media: generated five 3-second synthetic fixtures"
