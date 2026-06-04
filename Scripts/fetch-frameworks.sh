#!/usr/bin/env bash
#
# fetch-frameworks.sh — vendors the pinned TVVLCKit.xcframework into Frameworks/
# (gitignored). DECIDED in Plan 7a (spec §4.3); USED for the first time in Plan 7c.
#
# Approach: first-party stable VLCKit 3.x binary from videolan.org, vendored +
# embedded via XcodeGen (mirrors Nikud's llama.xcframework setup).
set -euo pipefail

VLCKIT_VERSION="3.6.0"          # stable 3.x (VLCMediaPlayer API). Revisit at VLCKit 4.0 stable.
DEST_DIR="Frameworks"
PINNED_URL="https://download.videolan.org/pub/cocoapods/prod/TVVLCKit-3.6.0-c73b779f-dd8bfdba.tar.xz"
EXPECTED_SHA256="90d85d85528286d7ef9cb27187e0e3027cccd602e8d2379587e65c698f04498c"

if [[ -z "$PINNED_URL" || -z "$EXPECTED_SHA256" ]]; then
  echo "fetch-frameworks: TVVLCKit pin not finalized." >&2
  exit 1
fi

mkdir -p "$DEST_DIR"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
echo "Downloading TVVLCKit ${VLCKIT_VERSION}…"
curl -fL --retry 3 --retry-delay 2 "$PINNED_URL" -o "$tmp/vlckit.tar.xz"
echo "${EXPECTED_SHA256}  $tmp/vlckit.tar.xz" | shasum -a 256 -c -
tar -xJf "$tmp/vlckit.tar.xz" -C "$tmp"
# The tarball roots at TVVLCKit-binary/; the xcframework lives inside it.
rm -rf "$DEST_DIR/TVVLCKit.xcframework"
mv "$tmp/TVVLCKit-binary/TVVLCKit.xcframework" "$DEST_DIR"/
echo "Done: $DEST_DIR/TVVLCKit.xcframework"
