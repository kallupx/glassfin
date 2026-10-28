#!/usr/bin/env bash
# Synthetic lavfi patterns and sine waves, dedicated to CC0. Never commit generated media.
# Reusable on Linux/macOS: generate-playback-media.sh MEDIA_DIRECTORY [FFMPEG_PATH]
set -euo pipefail
media_dir="${1:-${GLASSFIN_MEDIA_DIR:-}}"
ffmpeg_bin="${2:-${FFMPEG:-ffmpeg}}"
if [[ -z "$media_dir" ]] || ! command -v "$ffmpeg_bin" >/dev/null 2>&1; then
  echo "Usage: generate-playback-media.sh MEDIA_DIRECTORY [FFMPEG_PATH]" >&2
  exit 1
fi
encoders="$("$ffmpeg_bin" -hide_banner -encoders 2>/dev/null)"
for encoder in libx264 libx265 aac ac3 eac3 dca mpeg2video; do
  if [[ ! "$encoders" =~ [[:space:]]${encoder}[[:space:]] ]]; then
    echo "playback-media: required encoder '$encoder' is unavailable" >&2
    exit 1
  fi
done
mkdir -p "$media_dir/Movies"

generate() {
  local name="$1" duration="$2"
  shift 2
  mkdir -p "$(dirname "$media_dir/$name")"
  "$ffmpeg_bin" -y -hide_banner -loglevel error -fflags +bitexact \
    -f lavfi -i "testsrc=size=160x90:rate=12" \
    -f lavfi -i "sine=frequency=440:sample_rate=48000" \
    -t "$duration" -shortest -threads 1 -pix_fmt yuv420p \
    -fflags +bitexact -flags:v +bitexact -flags:a +bitexact -map_metadata -1 \
    -b:v 160k -b:a 96k -ar 48000 -ac 2 -g 24 "$@" "$media_dir/$name"
}
h264=(-c:v libx264 -preset ultrafast)
hevc=(-c:v libx265 -preset ultrafast -x265-params pools=none:frame-threads=1:log-level=error)
# F1/F3 are 60 s for resume/progress; F2/F4/F5/F6 stay below 10 s.
generate "Movies/Test Movie (2024).mp4" 60 "${h264[@]}" -c:a aac -movflags +faststart
generate "Movies/Glassfin HEVC EAC3 (2024).mp4" 6 "${hevc[@]}" -tag:v hvc1 -c:a eac3 -ac 6 -b:a 192k -movflags +faststart
generate "Movies/Glassfin Remux (2024).mkv" 60 "${h264[@]}" -c:a aac
# DTS must play through audio-only transcoding with video copied.
generate "Movies/Glassfin DTS (2024).mkv" 6 "${h264[@]}" -c:a dca -strict -2 -b:a 768k
# MPEG-2 is the canonical unsupported video.
generate "Movies/Glassfin Unsupported (2024).mkv" 6 -c:v mpeg2video -c:a aac
generate "Movies/Glassfin HEVC AC3 (2024).mkv" 6 "${hevc[@]}" -c:a ac3 -ac 6 -b:a 192k
for episode in 01 02 03; do
  generate "Shows/Glassfin Test Show (2026)/Season 01/Glassfin Test Show S01E${episode}.mp4" 60 \
    "${h264[@]}" -c:a aac -movflags +faststart
  cat > "$media_dir/Shows/Glassfin Test Show (2026)/Season 01/Glassfin Test Show S01E${episode}.nfo" <<EOF
<episodedetails><title>Episode ${episode}</title><season>1</season><episode>${episode#0}</episode><aired>2026-01-${episode}</aired></episodedetails>
EOF
done
generate "Shows/Glassfin Test Show (2026)/Season 02/Glassfin Test Show S02E01.mp4" 6 \
  "${h264[@]}" -c:a aac -movflags +faststart
cat > "$media_dir/Shows/Glassfin Test Show (2026)/Season 02/Glassfin Test Show S02E01.nfo" <<'EOF'
<episodedetails><title>Season 2 Episode 1</title><season>2</season><episode>1</episode><aired>2026-02-01</aired></episodedetails>
EOF
cat > "$media_dir/Shows/Glassfin Test Show (2026)/tvshow.nfo" <<'EOF'
<tvshow><title>Glassfin Test Show</title><year>2026</year><premiered>2026-01-01</premiered></tvshow>
EOF
echo "playback-media: generated six movies (F1/F3 60 s, others 6 s) and four episodes (Season 1: three 60 s; Season 2: one 6 s)"
