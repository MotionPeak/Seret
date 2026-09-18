#!/usr/bin/env bash
# Read-only. Works out why Chromium ignored --remote-debugging-port.
#
#   sudo bash ~/letterboxd-cdp-diagnose.sh
#
# Changes nothing, starts nothing, stops nothing.
set -uo pipefail
DOCKER=/usr/local/bin/docker
NAME=letterboxd-chromium

echo "=== 1. what the container was told to run ==="
"$DOCKER" inspect "$NAME" --format '{{range .Config.Env}}{{if eq (slice . 0 (min 11 (len .))) "CHROME_CLI="}}{{.}}{{end}}{{end}}' 2>/dev/null \
  || "$DOCKER" inspect "$NAME" --format '{{json .Config.Env}}' | tr ',' '\n' | grep -i chrome_cli

echo
echo "=== 2. the wrapper that actually launches chromium ==="
"$DOCKER" exec "$NAME" sh -c 'cat /usr/bin/wrapped-chromium 2>/dev/null | head -40' \
  || echo "(could not read the wrapper)"

echo
echo "=== 3. the REAL chromium command line, as the kernel sees it ==="
"$DOCKER" exec "$NAME" sh -c '
  for p in /proc/[0-9]*; do
    if tr "\0" " " < "$p/cmdline" 2>/dev/null | grep -q "^/usr/lib/chromium/chromium"; then
      tr "\0" "\n" < "$p/cmdline" | grep -nE "remote-debugging|user-data-dir|load-extension" \
        && echo "   (pid ${p##*/})" && break
    fi
  done' 2>/dev/null || echo "(could not read cmdline)"

echo
echo "=== 4. is anything listening on 9222 INSIDE the container? ==="
"$DOCKER" exec "$NAME" sh -c 'ss -tln 2>/dev/null | grep 9222 || netstat -tln 2>/dev/null | grep 9222 || echo "(nothing on 9222 inside)"' 2>/dev/null

echo
echo "=== 5. chromium version (the >=136 debug-port rule depends on it) ==="
"$DOCKER" exec "$NAME" sh -c '/usr/lib/chromium/chromium --version 2>/dev/null' || echo "(unknown)"

echo
echo "=== 6. does the profile still hold the Letterboxd session? ==="
"$DOCKER" exec "$NAME" sh -c 'ls -l /config/.config/chromium/Default/Cookies 2>/dev/null || echo "(no Cookies file at the expected path)"'
