#!/bin/zsh
# Renders every piece of Seret's brand art from Scripts/topshelf/art.js and installs it:
#   • the Top Shelf loop (Range) + its poster still  → Apps/SeretTopShelf/Resources/
#   • the tvOS Top Shelf images and layered app icon → Apps/SeretTV/Resources/Assets.xcassets/
#   • the iPhone/iPad app icon                       → Apps/SeretMobile/Resources/Assets.xcassets/
#
#   Scripts/topshelf/render.sh            # everything (the 4K video takes a few minutes)
#   Scripts/topshelf/render.sh --stills   # icons + stills only, skips the video
#
# Needs ffmpeg with libx265 (`brew install ffmpeg`).
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT=$PWD
HERE=$ROOT/Scripts/topshelf
WORK=$(mktemp -d -t seret-art)
trap 'rm -rf "$WORK"' EXIT

FPS=30; LOOP=16; VW=3840; VH=2160
SHELF=$ROOT/Apps/SeretTopShelf/Resources
BRAND="$ROOT/Apps/SeretTV/Resources/Assets.xcassets/App Icon & Top Shelf Image.brandassets"
MOBILE=$ROOT/Apps/SeretMobile/Resources/Assets.xcassets/AppIcon.appiconset

job() { printf '%s\t%s\t%s\t%s\t%s\n' "$@" >> "$WORK/jobs.tsv"; }

# Stills and icons.
job rangeStill 1920 1080 0 "$WORK/poster-1x.png"
job rangeStill 3840 2160 0 "$WORK/poster-2x.png"
job rangeStill 1920 720  0 "$WORK/shelf@1x.png"
job rangeStill 3840 1440 0 "$WORK/shelf@2x.png"
job rangeStill 2320 720  0 "$WORK/wide@1x.png"
job rangeStill 4640 1440 0 "$WORK/wide@2x.png"
job monoBack    400  240 0 "$WORK/back@1x.png"
job monoBack    800  480 0 "$WORK/back@2x.png"
job monoFrontTV 400  240 0 "$WORK/front@1x.png"
job monoFrontTV 800  480 0 "$WORK/front@2x.png"
job monoBack    1280 768 0 "$WORK/store-back.png"
job monoFrontTV 1280 768 0 "$WORK/store-front.png"
job monoPhone   1024 1024 0 "$WORK/phone.png"

if [[ "${1:-}" != "--stills" ]]; then
  for ((i = 0; i < FPS * LOOP; i++)); do
    job range $VW $VH $(printf '%.6f' $((i * 1.0 / FPS))) "$WORK/frames/$(printf '%05d' $i).png"
  done
fi

echo "Rendering $(wc -l < "$WORK/jobs.tsv" | tr -d ' ') images…"
swift "$HERE/render.swift" "$WORK/jobs.tsv"

opaque() { ffmpeg -loglevel error -y -i "$1" -pix_fmt rgb24 "$2"; }   # icons must carry no alpha
jpeg()   { ffmpeg -loglevel error -y -i "$1" -q:v 2 "$2"; }

mkdir -p "$SHELF"
jpeg "$WORK/poster-1x.png" "$SHELF/range-poster-1x.jpg"
jpeg "$WORK/poster-2x.png" "$SHELF/range-poster-2x.jpg"

opaque "$WORK/shelf@1x.png" "$BRAND/Top Shelf Image.imageset/shelf@1x.png"
opaque "$WORK/shelf@2x.png" "$BRAND/Top Shelf Image.imageset/shelf@2x.png"
opaque "$WORK/wide@1x.png"  "$BRAND/Top Shelf Image Wide.imageset/shelf@1x.png"
opaque "$WORK/wide@2x.png"  "$BRAND/Top Shelf Image Wide.imageset/shelf@2x.png"
opaque "$WORK/back@1x.png"  "$BRAND/App Icon.imagestack/Back.imagestacklayer/Content.imageset/icon.png"
opaque "$WORK/back@2x.png"  "$BRAND/App Icon.imagestack/Back.imagestacklayer/Content.imageset/icon@2x.png"
cp "$WORK/front@1x.png"     "$BRAND/App Icon.imagestack/Front.imagestacklayer/Content.imageset/icon.png"
cp "$WORK/front@2x.png"     "$BRAND/App Icon.imagestack/Front.imagestacklayer/Content.imageset/icon@2x.png"
opaque "$WORK/store-back.png" "$BRAND/App Icon - App Store.imagestack/Back.imagestacklayer/Content.imageset/icon.png"
cp "$WORK/store-front.png"  "$BRAND/App Icon - App Store.imagestack/Front.imagestacklayer/Content.imageset/icon.png"
opaque "$WORK/phone.png"    "$MOBILE/icon-1024.png"

if [[ "${1:-}" != "--stills" ]]; then
  echo "Encoding the loop…"
  # HEVC Main10 tagged hvc1 (what Apple's players expect); 10-bit keeps the dark gradients from banding.
  ffmpeg -loglevel error -y -framerate $FPS -i "$WORK/frames/%05d.png" \
    -c:v libx265 -preset slow -crf 20 -pix_fmt yuv420p10le -tag:v hvc1 \
    -x265-params log-level=error -movflags +faststart "$SHELF/range.mp4"
  ls -lh "$SHELF/range.mp4"
fi
echo "Done."
