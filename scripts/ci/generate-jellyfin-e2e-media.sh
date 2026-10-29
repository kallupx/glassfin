#!/usr/bin/env bash
# Generated test patterns, sine waves and subtitles, dedicated to CC0.
set -euo pipefail
media="${1:?media directory}"
ffmpeg="${2:?pinned ffmpeg executable}"
mkdir -p "$media/Movies" "$media/Shows/Glassfin Generated Show/Season 01"
subtitle="$media/generated.srt"
cat > "$subtitle" <<'SRT'
1
00:00:00,000 --> 00:00:05,500
Generated Glassfin test subtitle.
SRT
make_media() {
  local output="$1" duration="$2" audio="$3"
  "$ffmpeg" -nostdin -y -hide_banner -loglevel error \
    -f lavfi -i 'testsrc=size=160x90:rate=12' \
    -f lavfi -i 'sine=frequency=440:sample_rate=48000' \
    -f lavfi -i 'sine=frequency=880:sample_rate=48000' \
    -i "$subtitle" -t "$duration" \
    -map 0:v -map 1:a -map 2:a -map 3:s \
    -c:v libx264 -preset ultrafast -threads 1 -pix_fmt yuv420p -g 24 \
    -c:a "$audio" -strict -2 -b:a 768k -ac 2 -c:s srt \
    -metadata:s:a:0 language=eng -metadata:s:a:1 language=fin \
    -metadata:s:s:0 language=eng -disposition:a:0 0 -disposition:a:1 default \
    "$output"
}
# Match #47 by container/video/audio codecs. Keep F4's default audio DTS too.
make_media "$media/Movies/Glassfin Remux (2024).mkv" 60 aac
make_media "$media/Movies/Glassfin DTS (2024).mkv" 24 dca
for episode in 01 02; do
  make_media "$media/Shows/Glassfin Generated Show/Season 01/Glassfin Generated Show S01E${episode}.mkv" 6 aac
done
rm "$subtitle"
echo 'Generated F3 (60 s), F4 (24 s), and two episodes with two audio tracks and embedded subtitles.'
