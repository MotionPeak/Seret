#!/usr/bin/env bash
# A real, persistent Chromium on the NAS, for pushing ratings to Letterboxd.
#
#   sudo bash ~/letterboxd-chromium-setup.sh
#
# Why this exists: Cloudflare refuses Letterboxd's /s/ endpoints to any non-browser client. Measured
# with a full valid session, a cf_clearance token and Chrome's exact User-Agent, curl still gets 403
# at 5,736 bytes — byte-identical to anonymous — while a real browser on the same cookie reaches the
# application. So the pusher has to BE a browser. This is that browser.
#
# Headed Chromium under a virtual display, not headless: headless is the variant Cloudflare
# detects. You sign in once through the web UI, which solves the challenge interactively and banks
# cf_clearance in a persistent profile that survives restarts.
#
# This stage deliberately does NOT expose the DevTools port. Sign in and confirm the browser can
# reach /s/ first; wiring SeretForever to drive it comes after that, and exposes CDP only on the
# docker network.
set -euo pipefail

DOCKER=/usr/local/bin/docker
NAME=letterboxd-chromium
# A NAMED VOLUME, not a bind mount under /volume1/docker. That path carries a Synology ACL (the
# trailing "+" on its mode) which denies the container even when POSIX says 0777 and the owner is
# right — the image's init fails with `mkdir: cannot create directory '/config/Desktop'`, the
# desktop never starts, and Chromium ends up a zombie. Docker-managed storage has none of that.
VOLUME=letterboxd-chromium-config
WEB_PORT=3010          # container 3000, plain HTTP — the frontend refuses to run on it
TLS_PORT=3011          # container 3001, HTTPS — this is the one that actually works

if [ "$(id -u)" -ne 0 ]; then
  echo "!! Run with sudo: sudo bash $0" >&2
  exit 1
fi
[ -x "$DOCKER" ] || { echo "!! no docker at $DOCKER" >&2; exit 1; }

echo "==> ensuring volume $VOLUME"
"$DOCKER" volume create "$VOLUME" >/dev/null

echo "==> pulling lscr.io/linuxserver/chromium (about 1 GB, a few minutes on the J4125)"
"$DOCKER" pull lscr.io/linuxserver/chromium:latest

echo "==> recreating container"
"$DOCKER" rm -f "$NAME" >/dev/null 2>&1 || true
"$DOCKER" run -d --name "$NAME" --restart unless-stopped \
  -e PUID=1026 -e PGID=100 -e TZ=Asia/Jerusalem \
  -e CHROME_CLI="https://letterboxd.com/sign-in/" \
  -v "$VOLUME:/config" \
  -p ${WEB_PORT}:3000 \
  -p ${TLS_PORT}:3001 \
  --shm-size=1g \
  --security-opt seccomp=unconfined \
  lscr.io/linuxserver/chromium:latest >/dev/null

echo "==> waiting for the web UI"
UI_UP=no
for _ in $(seq 1 45); do
  # -k: the image ships a self-signed certificate, which is fine on a LAN.
  if curl -fsSk "https://localhost:${TLS_PORT}/" >/dev/null 2>&1; then UI_UP=yes; break; fi
  sleep 2
done
if [ "$UI_UP" != yes ]; then
  echo "!! the web UI did not come up in 90s. Logs:" >&2
  "$DOCKER" logs --tail 40 "$NAME" >&2
  exit 1
fi
echo "==> web UI up"

# The port listening is NOT the same as the browser running. Last time the frontend served fine
# while Chromium was a zombie, so check for a live, non-defunct chromium process before claiming
# success.
echo "==> waiting for Chromium itself"
for _ in $(seq 1 30); do
  if "$DOCKER" top "$NAME" 2>/dev/null | grep -i chromium | grep -qv defunct; then
    echo "==> Chromium is running"
    echo
    echo "    Open  https://192.168.1.179:${TLS_PORT}/   (accept the self-signed certificate)"
    echo "    Sign in to Letterboxd in that browser. Once."
    echo
    echo "    Then point it at https://letterboxd.com/s/autocompletefilm — a short blob of text"
    echo "    means this works; \"Just a moment...\" means Cloudflare refuses it even as a real"
    echo "    browser, and the iPhone is the answer instead."
    exit 0
  fi
  sleep 2
done

echo "!! Chromium never started (or died). Logs:" >&2
"$DOCKER" logs --tail 40 "$NAME" >&2
echo >&2
echo "   Processes seen in the container:" >&2
"$DOCKER" top "$NAME" >&2 2>/dev/null || true
exit 1
