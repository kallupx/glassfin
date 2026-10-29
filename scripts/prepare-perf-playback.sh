#!/usr/bin/env bash
# CC0 lavfi video/tones and synthetic subtitles. Uses files only, never a server.
# Usage: scripts/prepare-perf-playback.sh OUTPUT_DIRECTORY [DURATION_SECONDS]
set -euo pipefail
if [[ $# -lt 1 || $# -gt 2 || ! "${2:-600}" =~ ^[1-9][0-9]*$ ]]; then
  echo "Usage: scripts/prepare-perf-playback.sh OUTPUT_DIRECTORY [DURATION_SECONDS]" >&2
  exit 2
fi
perf_media_dir="$1"
perf_duration="${2:-600}"
perf_work="$(mktemp -d)"
trap 'rm -rf "$perf_work"' EXIT
native="$perf_media_dir/Perf Native Tracks"
remux="$perf_media_dir/Perf Server Remux"
transcode="$perf_media_dir/Perf Video Transcode"
mkdir -p "$native" "$remux" "$transcode"
python3 - "$perf_work" "$perf_duration" "$perf_media_dir" <<'PY'
from pathlib import Path
import sys

work, seconds, root = Path(sys.argv[1]), int(sys.argv[2]), Path(sys.argv[3])
hours, seconds = divmod(seconds, 3600)
minutes, seconds = divmod(seconds, 60)
end = f'{hours:02d}:{minutes:02d}:{seconds:02d},000'
for name in ('Primary', 'Alternate'):
    (work / f'{name}.srt').write_text(f'1\n00:00:00,000 --> {end}\n{name} subtitle sample\n')
for title in ('Perf Native Tracks', 'Perf Server Remux', 'Perf Video Transcode'):
    (root / title / 'movie.nfo').write_text(f'<movie><title>{title}</title><year>2026</year></movie>\n')
PY
ffmpeg -nostdin -y -hide_banner -loglevel error \
  -f lavfi -i 'testsrc=size=320x180:rate=30' \
  -f lavfi -i 'sine=frequency=440:sample_rate=48000' \
  -f lavfi -i 'sine=frequency=880:sample_rate=48000' \
  -i "$perf_work/Primary.srt" -i "$perf_work/Alternate.srt" \
  -map 0:v -map 1:a -map 2:a -map 3:s -map 4:s -t "$perf_duration" \
  -c:v libx264 -preset ultrafast -pix_fmt yuv420p -threads 1 -g 30 \
  -c:a aac -b:a 96k -ar 48000 -ac 2 -c:s mov_text \
  -map_metadata -1 \
  -metadata:s:a:0 language=eng -metadata:s:a:0 title='Primary audio' \
  -metadata:s:a:1 language=fin -metadata:s:a:1 title='Alternate audio' \
  -metadata:s:s:0 language=eng -metadata:s:s:0 title='Primary subtitles' \
  -metadata:s:s:1 language=fin -metadata:s:s:1 title='Alternate subtitles' \
  -disposition:a:0 default -disposition:a:1 0 -disposition:s:0 0 -disposition:s:1 0 \
  -movflags +faststart "$native/Perf Native Tracks.mp4"
# A container-only copy exercises server DirectStream, with external VTT conversion available.
ffmpeg -nostdin -y -hide_banner -loglevel error \
  -i "$native/Perf Native Tracks.mp4" -map 0:v -map 0:a -c copy -map_metadata -1 \
  -metadata:s:a:0 language=eng -metadata:s:a:0 title='Primary audio' \
  -metadata:s:a:1 language=fin -metadata:s:a:1 title='Alternate audio' \
  "$remux/Perf Server Remux.mkv"
cp "$perf_work/Primary.srt" "$remux/Perf Server Remux.eng.srt"
cp "$perf_work/Alternate.srt" "$remux/Perf Server Remux.fin.srt"
# MPEG-2 is outside the runtime DirectPlay profile and requests video encoding in full M08a.
ffmpeg -nostdin -y -hide_banner -loglevel error \
  -f lavfi -i 'testsrc=size=320x180:rate=30' -t "$perf_duration" \
  -c:v mpeg2video -q:v 4 -pix_fmt yuv420p -threads 1 -an -map_metadata -1 \
  "$transcode/Perf Video Transcode.mkv"
echo 'Prepared three synthetic playback fixtures: native tracks, server remux, video transcode.'
