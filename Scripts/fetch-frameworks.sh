#!/usr/bin/env bash
#
# fetch-frameworks.sh — vendors the pinned VLCKit.xcframework into Frameworks/
# (gitignored). DECIDED in Plan 7a; USED for the first time in Plan 7c.
#
# VLCKit 4.x (Metal renderer). 3.x's OpenGL ES renderer touches the CAEAGLLayer on its
# render thread, which tvOS 18+/26 blocks ("modifying a view's layer off the main thread"),
# producing black video. 4.x renders with Metal and is unaffected. 4.x is pre-release (alpha);
# revisit the pin at the 4.0 stable release.
#
# Approach: first-party VLCKit binary from videolan.org, vendored + embedded via XcodeGen
# (mirrors Nikud's llama.xcframework setup).
set -euo pipefail

VLCKIT_VERSION="4.0.0a19"        # 4.x = Metal renderer; 3.x OpenGL ES is broken on tvOS 26. Alpha — revisit at 4.0 stable.
DEST_DIR="Frameworks"
PINNED_URL="https://download.videolan.org/pub/cocoapods/unstable/VLCKit-4.0.0a19-d7597c1706-85a537d69.tar.xz"
EXPECTED_SHA256="1172078a43150af202c31feb62db3d6687f242d3aa048cce1b899f51c4f14142"

if [[ -z "$PINNED_URL" || -z "$EXPECTED_SHA256" ]]; then
  echo "fetch-frameworks: VLCKit pin not finalized." >&2
  exit 1
fi

mkdir -p "$DEST_DIR"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
echo "Downloading VLCKit ${VLCKIT_VERSION}… (~500 MB unified xcframework)"
curl -fL --retry 3 --retry-delay 2 "$PINNED_URL" -o "$tmp/vlckit.tar.xz"
echo "${EXPECTED_SHA256}  $tmp/vlckit.tar.xz" | shasum -a 256 -c -
tar -xJf "$tmp/vlckit.tar.xz" -C "$tmp"
# The tarball roots at VLCKit-binary/; the xcframework lives inside it.
rm -rf "$DEST_DIR/TVVLCKit.xcframework" "$DEST_DIR/VLCKit.xcframework"
mv "$tmp/VLCKit-binary/VLCKit.xcframework" "$DEST_DIR"/
echo "Done: $DEST_DIR/VLCKit.xcframework"
