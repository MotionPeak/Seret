#!/usr/bin/env bash
# Make the browser's DevTools port reachable.
#
#   sudo bash ~/letterboxd-cdp-bridge.sh
#
# Chromium always binds DevTools to 127.0.0.1 inside the container and ignores
# --remote-debugging-address (the flag was removed). Docker's port publish forwards to the
# container's eth0, where nothing listens — so the port looked open from the host and refused every
# connection. A socat sidecar sharing the browser's network namespace listens on eth0 and forwards
# to that loopback.
#
# The browser container is recreated to join a user-defined network and publish the bridged port.
# The profile is in a named volume, so the Letterboxd session survives — it already survived the
# last recreate.
set -euo pipefail

DOCKER=/usr/local/bin/docker
NAME=letterboxd-chromium
PROXY=letterboxd-cdp-proxy
NET=letterboxd-net
VOLUME=letterboxd-chromium-config
WEB_PORT=3010
TLS_PORT=3011
CDP_IN=9222      # where Chromium listens, on container loopback
CDP_OUT=9223     # what the sidecar exposes on the container's eth0

if [ "$(id -u)" -ne 0 ]; then echo "!! run with sudo" >&2; exit 1; fi

echo "==> network $NET"
"$DOCKER" network create "$NET" >/dev/null 2>&1 || true

echo "==> recreating the browser on that network"
"$DOCKER" rm -f "$PROXY" >/dev/null 2>&1 || true
"$DOCKER" rm -f "$NAME"  >/dev/null 2>&1 || true
"$DOCKER" run -d --name "$NAME" --restart unless-stopped \
  --network "$NET" \
  -e PUID=1026 -e PGID=100 -e TZ=Asia/Jerusalem \
  -e CHROME_CLI="--user-data-dir=/config/.config/chromium --remote-debugging-port=${CDP_IN} https://letterboxd.com/" \
  -v "$VOLUME:/config" \
  -p ${WEB_PORT}:3000 \
  -p ${TLS_PORT}:3001 \
  -p 127.0.0.1:${CDP_OUT}:${CDP_OUT} \
  --shm-size=1g \
  --security-opt seccomp=unconfined \
  lscr.io/linuxserver/chromium:latest >/dev/null

echo "==> waiting for Chromium to open DevTools on its loopback"
OK=no
for _ in $(seq 1 90); do
  if "$DOCKER" exec "$NAME" sh -c "ss -tln 2>/dev/null | grep -q 127.0.0.1:${CDP_IN}"; then OK=yes; break; fi
  sleep 2
done
if [ "$OK" != yes ]; then
  echo "!! Chromium never opened ${CDP_IN} internally. Logs:" >&2
  "$DOCKER" logs --tail 15 "$NAME" 2>&1 | grep -viE "gamepad|js_config|interposer" | tail -10 >&2
  exit 1
fi
echo "==> DevTools is listening inside"

echo "==> starting the socat bridge (shares the browser's network namespace)"
"$DOCKER" run -d --name "$PROXY" --restart unless-stopped \
  --network "container:${NAME}" \
  alpine/socat \
  "tcp-listen:${CDP_OUT},fork,reuseaddr" "tcp-connect:127.0.0.1:${CDP_IN}" >/dev/null

echo "==> verifying end to end"
for _ in $(seq 1 30); do
  if curl -fsS -m 3 "http://127.0.0.1:${CDP_OUT}/json/version" 2>/dev/null | grep -q Browser; then
    echo "==> WORKING:"
    curl -fsS "http://127.0.0.1:${CDP_OUT}/json/version" | tr ',' '\n' | grep -E '"Browser"|webSocketDebuggerUrl' | sed 's/^/    /'
    echo
    echo "    Other containers on '$NET' reach it as  ${NAME}:${CDP_OUT}"
    echo "    On the NAS itself it is                 127.0.0.1:${CDP_OUT}"
    echo "    It is NOT on your LAN."
    exit 0
  fi
  sleep 2
done

echo "!! the bridge did not answer. socat logs:" >&2
"$DOCKER" logs --tail 20 "$PROXY" >&2 2>/dev/null || true
exit 1
