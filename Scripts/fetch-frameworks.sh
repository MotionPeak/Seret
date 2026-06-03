#!/usr/bin/env bash
#
# fetch-frameworks.sh — vendors the pinned TVVLCKit.xcframework into Frameworks/
# (gitignored). DECIDED in Plan 7a (spec §4.3); USED for the first time in Plan 7c.
# NOT required for 7a's sign-in build.
#
# Approach: first-party stable VLCKit 3.x binary from videolan.org, vendored +
# embedded via XcodeGen (mirrors Nikud's llama.xcframework setup). Plan 7c finalizes
# the exact tarball URL + sha256 and flips this on.
set -euo pipefail

VLCKIT_VERSION="3.6.0"          # stable 3.x (VLCMediaPlayer API). Revisit at VLCKit 4.0 stable.
DEST_DIR="Frameworks"
PINNED_URL=""                   # Plan 7c: exact https://download.videolan.org/... tarball URL
EXPECTED_SHA256=""              # Plan 7c: sha256 of the tarball (reproducible builds)

if [[ -z "$PINNED_URL" || -z "$EXPECTED_SHA256" ]]; then
  echo "fetch-frameworks: TVVLCKit pin not finalized (Plan 7c sets PINNED_URL + EXPECTED_SHA256)." >&2
  echo "  Intended: TVVLCKit ${VLCKIT_VERSION} -> ${DEST_DIR}/TVVLCKit.xcframework" >&2
  exit 1
fi

mkdir -p "$DEST_DIR"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
echo "Downloading TVVLCKit ${VLCKIT_VERSION}…"
curl -fL --retry 3 --retry-delay 2 "$PINNED_URL" -o "$tmp/vlckit.tar.xz"
echo "${EXPECTED_SHA256}  $tmp/vlckit.tar.xz" | shasum -a 256 -c -
tar -xJf "$tmp/vlckit.tar.xz" -C "$tmp"
# Plan 7c: uncomment + verify the extracted directory name, then drop the guard below:
# mv "$tmp"/TVVLCKit.xcframework "$DEST_DIR"/
# echo "Done."
echo "fetch-frameworks: Plan 7c must add the 'mv' step above before this script is complete." >&2
exit 1
