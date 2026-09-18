#!/usr/bin/env bash
# Back up the signed-in Chromium profile, then re-create the container with the DevTools port
# enabled so SeretServer can drive it.
#
#   sudo bash ~/letterboxd-enable-cdp.sh
#
# The profile lives in a named volume and survives the recreate, so the Letterboxd session should
# come back signed in. The backup exists because "should" is not "will", and re-signing in is a
# chore.
#
# The DevTools port is published to 127.0.0.1 ONLY. Anything that can reach that port can drive the
# browser as you, so it does not go on the LAN. SeretServer will reach it over a docker network
# instead, which is added when that wiring happens.
set -euo pipefail

DOCKER=/usr/local/bin/docker
NAME=letterboxd-chromium
VOLUME=letterboxd-chromium-config
WEB_PORT=3010
TLS_PORT=3011
CDP_PORT=9222
BACKUP=/volume1/docker/letterboxd-chromium-profile-$(date +%Y%m%d-%H%M%S).tgz

if [ "$(id -u)" -ne 0 ]; then echo "!! run with sudo" >&2; exit 1; fi
[ -x "$DOCKER" ] || { echo "!! no docker at $DOCKER" >&2; exit 1; }

echo "==> backing up the signed-in profile to $BACKUP"
"$DOCKER" run --rm -v "$VOLUME":/from -v /volume1/docker:/to alpine \
  tar czf "/to/$(basename "$BACKUP")" -C /from . 2>/dev/null
ls -lh "$BACKUP" | awk '{print "    " $5, $9}'

echo "==> recreating with the DevTools port"
"$DOCKER" rm -f "$NAME" >/dev/null 2>&1 || true
# --user-data-dir is passed EXPLICITLY at the profile's existing location. Chrome 136+ refuses a
# debug port when the profile is the implicit default one; naming the same path satisfies that
# check without moving the profile, so the session is preserved.
"$DOCKER" run -d --name "$NAME" --restart unless-stopped \
  -e PUID=1026 -e PGID=100 -e TZ=Asia/Jerusalem \
  -e CHROME_CLI="--user-data-dir=/config/.config/chromium --remote-debugging-port=${CDP_PORT} --remote-debugging-address=0.0.0.0 https://letterboxd.com/" \
  -v "$VOLUME:/config" \
  -p ${WEB_PORT}:3000 \
  -p ${TLS_PORT}:3001 \
  -p 127.0.0.1:${CDP_PORT}:${CDP_PORT} \
  --shm-size=1g \
  --security-opt seccomp=unconfined \
  lscr.io/linuxserver/chromium:latest >/dev/null

echo "==> waiting for the web UI"
for _ in $(seq 1 45); do
  curl -fsSk "https://localhost:${TLS_PORT}/" >/dev/null 2>&1 && break
  sleep 2
done

echo "==> waiting for DevTools (up to 3 minutes; the desktop is slow to come up on a J4125)"
for _ in $(seq 1 90); do
  if curl -fsS "http://127.0.0.1:${CDP_PORT}/json/version" 2>/dev/null | grep -q Browser; then
    echo "==> DevTools is up:"
    curl -fsS "http://127.0.0.1:${CDP_PORT}/json/version" | tr ',' '\n' | grep -E 'Browser|User-Agent' | sed 's/^/    /'
    echo
    echo "    Open https://192.168.1.179:${TLS_PORT}/ and confirm Letterboxd still shows you"
    echo "    signed in. If it does not, the backup above restores the old profile."
    exit 0
  fi
  sleep 2
done

echo "!! DevTools never came up. Chromium may have refused the debug flag." >&2
echo "   Logs:" >&2
"$DOCKER" logs --tail 20 "$NAME" 2>&1 | grep -viE "gamepad|js_config|interposer" | tail -12 >&2
echo >&2
echo "   Your profile backup is at $BACKUP" >&2
exit 1
