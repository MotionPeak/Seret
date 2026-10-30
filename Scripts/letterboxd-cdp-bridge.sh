#!/usr/bin/env bash
# Make the browser's DevTools port reachable — and keep it reachable across NAS reboots.
#
#   sudo bash ~/letterboxd-cdp-bridge.sh
#
# Chromium always binds DevTools to 127.0.0.1 inside the container and ignores
# --remote-debugging-address (the flag was removed). Docker's port publish forwards to the
# container's eth0, where nothing listens — so the port looked open from the host and refused every
# connection. A relay inside the browser's network namespace listens on eth0 and forwards to that
# loopback.
#
# The relay used to be a socat sidecar container joined with `--network container:…`. That broke
# on the first NAS reboot (2026-10-25): Docker brought both containers back, but the sidecar no
# longer forwarded, and the port reset every connection until someone restarted it by hand. Now
# the relay is a service INSIDE the browser container (the image's s6 supervisor runs whatever is
# in /custom-services.d), so it starts, stops and restarts with the browser — there is no pairing
# left to break. The same service watches Chromium: DevTools gone for 10 minutes stops the
# container, and `--restart unless-stopped` brings it back with a fresh Chromium.
#
# The browser container is recreated each run. The profile is in a named volume, so the Letterboxd
# session survives — it has survived every recreate so far.
set -euo pipefail

DOCKER=${DOCKER:-/usr/local/bin/docker}
NAME=letterboxd-chromium
OLD_PROXY=letterboxd-cdp-proxy   # the sidecar this replaces; removed if present
NET=letterboxd-net
VOLUME=letterboxd-chromium-config
SERVICES=${SERVICES:-/volume1/docker/letterboxd-chromium/custom-services.d}
WEB_PORT=3010
TLS_PORT=3011
CDP_IN=9222      # where Chromium listens, on container loopback
CDP_OUT=9223     # what the relay exposes on the container's eth0

if [ "$(id -u)" -ne 0 ]; then echo "!! run with sudo" >&2; exit 1; fi

echo "==> installing the relay service in $SERVICES"
mkdir -p "$SERVICES"
cat > "$SERVICES/cdp-relay" <<'SERVICE'
#!/usr/bin/with-contenv bash
# DevTools relay + Chromium watchdog. Installed by letterboxd-cdp-bridge.sh — edit it there.
# CDP_IN / CDP_OUT come from the container's environment.
for py in /usr/bin/python3 /lsiopy/bin/python3 "$(command -v python3)"; do
  [ -x "$py" ] || continue
  exec "$py" -u - <<'PY'
import asyncio, os, subprocess, time

LISTEN, TARGET = int(os.environ["CDP_OUT"]), int(os.environ["CDP_IN"])
GRACE = int(os.environ.get("CDP_WATCHDOG_GRACE", 300))   # Chromium takes a while to start
DOWN_LIMIT = int(os.environ.get("CDP_WATCHDOG_LIMIT", 600))
CHECK_EVERY = 30

def log(message):
    print(f"[cdp-relay] {message}", flush=True)

async def pipe(reader, writer):
    try:
        while data := await reader.read(65536):
            writer.write(data)
            await writer.drain()
    except (ConnectionError, OSError):
        pass
    finally:
        writer.close()

async def relay(client_reader, client_writer):
    try:
        upstream_reader, upstream_writer = await asyncio.open_connection("127.0.0.1", TARGET)
    except OSError:
        client_writer.close()   # Chromium not up (yet): the caller sees a closed socket and retries
        return
    await asyncio.gather(pipe(client_reader, upstream_writer), pipe(upstream_reader, client_writer))

async def devtools_up():
    try:
        _, writer = await asyncio.wait_for(asyncio.open_connection("127.0.0.1", TARGET), 5)
        writer.close()
        return True
    except (OSError, asyncio.TimeoutError):
        return False

def stop_container():
    # Halting s6 ends PID 1; with --restart unless-stopped Docker starts the container again.
    for halt in (["/run/s6/basedir/bin/halt"], ["kill", "-TERM", "1"]):
        try:
            subprocess.run(halt, check=True, timeout=30)
            return
        except Exception as error:
            log(f"{halt[0]} failed: {error}")

async def watchdog():
    started = last_up = time.monotonic()
    was_up = False
    while True:
        await asyncio.sleep(CHECK_EVERY)
        now = time.monotonic()
        if await devtools_up():
            if not was_up:
                log(f"DevTools is up on 127.0.0.1:{TARGET}")
            last_up, was_up = now, True
            continue
        if was_up:
            log("DevTools stopped answering")
        was_up = False
        if now - started > GRACE and now - last_up > DOWN_LIMIT:
            log(f"DevTools down for {int(now - last_up)}s, stopping the container to restart Chromium")
            stop_container()
            return

async def main():
    server = await asyncio.start_server(relay, "0.0.0.0", LISTEN, reuse_address=True)
    log(f"relaying 0.0.0.0:{LISTEN} -> 127.0.0.1:{TARGET}")
    async with server:
        await asyncio.gather(server.serve_forever(), watchdog())

asyncio.run(main())
PY
done
echo "[cdp-relay] no python3 in the image, cannot relay DevTools" >&2
sleep 300   # s6 restarts the service when it exits; do not spin
SERVICE
# The image skips custom services that are not owned by root or that others can write.
chown -R root:root "$(dirname "$SERVICES")"
chmod 755 "$(dirname "$SERVICES")" "$SERVICES" "$SERVICES/cdp-relay"

echo "==> network $NET"
"$DOCKER" network create "$NET" >/dev/null 2>&1 || true

echo "==> recreating the browser on that network, relay inside"
"$DOCKER" rm -f "$OLD_PROXY" >/dev/null 2>&1 || true
"$DOCKER" rm -f "$NAME"      >/dev/null 2>&1 || true
"$DOCKER" run -d --name "$NAME" --restart unless-stopped \
  --network "$NET" \
  -e PUID=1026 -e PGID=100 -e TZ=Asia/Jerusalem \
  -e CHROME_CLI="--user-data-dir=/config/.config/chromium --remote-debugging-port=${CDP_IN} https://letterboxd.com/" \
  -e CDP_IN=${CDP_IN} -e CDP_OUT=${CDP_OUT} \
  ${CDP_WATCHDOG_GRACE:+-e CDP_WATCHDOG_GRACE=$CDP_WATCHDOG_GRACE} \
  ${CDP_WATCHDOG_LIMIT:+-e CDP_WATCHDOG_LIMIT=$CDP_WATCHDOG_LIMIT} \
  -v "$VOLUME:/config" \
  -v "$SERVICES:/custom-services.d:ro" \
  -p ${WEB_PORT}:3000 \
  -p ${TLS_PORT}:3001 \
  -p 127.0.0.1:${CDP_OUT}:${CDP_OUT} \
  --shm-size=1g \
  --security-opt seccomp=unconfined \
  lscr.io/linuxserver/chromium:latest >/dev/null

echo "==> verifying end to end (Chromium takes a minute or two to start)"
for _ in $(seq 1 90); do
  if curl -fsS -m 3 "http://127.0.0.1:${CDP_OUT}/json/version" 2>/dev/null | grep -q Browser; then
    echo "==> WORKING:"
    curl -fsS "http://127.0.0.1:${CDP_OUT}/json/version" | tr ',' '\n' | grep -E '"Browser"|webSocketDebuggerUrl' | sed 's/^/    /'
    echo
    echo "    Other containers on '$NET' reach it as  ${NAME}:${CDP_OUT}"
    echo "    On the NAS itself it is                 127.0.0.1:${CDP_OUT}"
    echo "    It is NOT on your LAN."
    echo "    It comes back by itself after a reboot; nothing to re-run."
    exit 0
  fi
  sleep 2
done

echo "!! the relay did not answer. Relay and browser logs:" >&2
"$DOCKER" logs --tail 60 "$NAME" 2>&1 | grep -E "cdp-relay|custom|rror" | tail -15 >&2 || true
exit 1
