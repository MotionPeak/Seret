#!/bin/zsh
# Renders the launch intro (`ART.introWide` / `ART.introTall` in art.js) to one video per screen
# shape and installs each where its app bundles it:
#   • Apple TV       3840×2160 @ 50 fps → Apps/SeretTV/Resources/Intro/intro-wide.mp4
#   • Mac            2880×1800 @ 60 fps → Apps/SeretMac/Resources/Intro/intro-wide.mp4
#   • iPad landscape 2732×2048 @ 60 fps → Apps/SeretMobile/Resources/Intro/intro-wide.mp4
#   • iPad portrait  2048×2732 @ 60 fps → Apps/SeretMobile/Resources/Intro/intro-tall-pad.mp4
#   • iPhone         1290×2796 @ 60 fps → Apps/SeretMobile/Resources/Intro/intro-tall-phone.mp4
# The app picks the file nearest its window's shape and fills the window with it.
#
# The TV gets 50 fps because its interface runs at 50 Hz (a 60 fps dive judders there); the rest
# are 60 fps, which ProMotion's 120 Hz divides evenly.
#
#   Scripts/topshelf/render-intro.sh          # every video (a few minutes)
#   Scripts/topshelf/render-intro.sh tv       # just one: tv | mac | pad-wide | pad-tall | phone
#
# Needs ffmpeg with libx265 (`brew install ffmpeg`).
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT=$PWD
HERE=$ROOT/Scripts/topshelf
WORK=$(mktemp -d -t seret-intro)
trap 'rm -rf "$WORK"' EXIT

DURATION=3.4   # INTRO in art.js

#        name     kind       width height fps  output
TARGETS=(
  "tv       introWide  3840  2160  50  Apps/SeretTV/Resources/Intro/intro-wide.mp4"
  "mac      introWide  2880  1800  60  Apps/SeretMac/Resources/Intro/intro-wide.mp4"
  "pad-wide introWide  2732  2048  60  Apps/SeretMobile/Resources/Intro/intro-wide.mp4"
  "pad-tall introTall  2048  2732  60  Apps/SeretMobile/Resources/Intro/intro-tall-pad.mp4"
  "phone    introTall  1290  2796  60  Apps/SeretMobile/Resources/Intro/intro-tall-phone.mp4"
)

for line in "${TARGETS[@]}"; do
  read -r name kind w h fps out <<< "$line"
  [[ -n "${1:-}" && "$1" != "$name" ]] && continue
  frames=$(printf '%.0f' $((DURATION * fps)))
  : > "$WORK/jobs.tsv"
  for ((i = 0; i <= frames; i++)); do
    printf '%s\t%s\t%s\t%.6f\t%s\n' $kind $w $h $((i * 1.0 / fps)) "$WORK/$name/$(printf '%05d' $i).png" >> "$WORK/jobs.tsv"
  done
  echo "$name: rendering $((frames + 1)) frames at ${w}×${h}…"
  swift "$HERE/render.swift" "$WORK/jobs.tsv"
  mkdir -p "$(dirname "$ROOT/$out")"
  # HEVC Main10 tagged hvc1 (what Apple's players expect); 10-bit keeps the dark gradients from
  # banding. No audio track, so playing it never touches the audio session.
  ffmpeg -loglevel error -y -framerate $fps -i "$WORK/$name/%05d.png" -an \
    -c:v libx265 -preset slow -crf 20 -pix_fmt yuv420p10le -tag:v hvc1 \
    -x265-params log-level=error -movflags +faststart "$ROOT/$out"
  ls -lh "$ROOT/$out"
  rm -rf "$WORK/$name"
done
echo "Done."
