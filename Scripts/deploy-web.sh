#!/usr/bin/env bash
# One-shot deploy for SeretServer on the Synology NAS.
#
#   cd ~/Seret && git pull && sudo bash Scripts/deploy-web.sh <TMDB_API_KEY>
#
# Recovers RD_TOKEN, TMDB_API_KEY and every optional setting from the currently-running container,
# so a redeploy needs nothing retyped and never silently drops one. Optional env, passed once with
# `sudo -E` and kept from then on:
#   SERET_WEB_PASSWORD=…      the web page's password
#   OMDB_API_KEY=…            the detail page's IMDb / Rotten Tomatoes / Metacritic row
#   OPENSUBTITLES_API_KEY=…   "Hebrew · Matched" on versions (built-in detection runs without it)
#   OPENSUBTITLES_API_KEY=xxxx sudo -E bash Scripts/deploy-web.sh
set -euo pipefail

# DSM does not put /usr/local/bin on root's PATH under sudo, and that is where docker lives. Every
# `docker` below depends on this.
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"
command -v docker >/dev/null || { echo "!! no docker on PATH ($PATH)" >&2; exit 1; }

# The running container's value for one setting, or nothing.
from_container() {
  docker inspect seret-web --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null \
    | sed -n "s/^$1=//p" | head -1 || true
}

TMDB_KEY="${1:-${TMDB_API_KEY:-}}"
# Recover it from the running container the same way RD_TOKEN is recovered below, so a redeploy
# needs no secrets retyped — and none end up in shell history.
if [ -z "$TMDB_KEY" ]; then
  TMDB_KEY="$(from_container TMDB_API_KEY)"
  [ -n "$TMDB_KEY" ] && echo "==> recovered TMDB_API_KEY from the existing container (${#TMDB_KEY} chars)"
fi
if [ -z "$TMDB_KEY" ]; then
  # Say WHICH thing is missing rather than just printing usage — the three causes need different
  # fixes and "usage:" sends you looking for the wrong one.
  if ! docker inspect seret-web >/dev/null 2>&1; then
    echo "!! no 'seret-web' container to recover from — pass the key once:" >&2
  else
    echo "!! the running seret-web has no TMDB_API_KEY in its environment — pass it once:" >&2
  fi
  echo "   sudo bash Scripts/deploy-web.sh <TMDB_API_KEY>" >&2
  exit 1
fi

# Checked against TMDB before anything is torn down. A placeholder or a typo otherwise produces a
# container that starts, serves, and silently has no metadata at all — no posters, no merged
# duplicates, titles keyed off the filename — which looks like a library bug, not a bad key.
if ! curl -fsS -m 15 "https://api.themoviedb.org/3/configuration?api_key=$TMDB_KEY" >/dev/null; then
  echo "!! TMDB rejected that key (${#TMDB_KEY} chars) - nothing was changed. Pass a working one:" >&2
  echo "   sudo bash Scripts/deploy-web.sh <TMDB_API_KEY>" >&2
  exit 1
fi
echo "==> TMDB accepted the key"

# --- recover the RD token from the existing container -----------------------------------------
RD="${RD_TOKEN:-}"
if [ -z "$RD" ]; then
  RD="$(from_container RD_TOKEN)"
fi
if [ -z "$RD" ] || [ "$RD" = "PASTE_YOUR_TOKEN" ]; then
  echo "!! Could not recover a usable RD_TOKEN from the running 'seret-web' container." >&2
  echo "   Re-run as: RD_TOKEN='<your-rd-token>' sudo -E bash Scripts/deploy-web.sh <TMDB_API_KEY>" >&2
  exit 1
fi
echo "==> recovered RD_TOKEN from the existing container (${#RD} chars)"

# --- optional settings: passed now, else kept from the existing container ------------------------
# Only passed-in values used to count, so a redeploy without `sudo -E` quietly dropped the ratings
# row and the web password.
for name in SERET_WEB_PASSWORD OMDB_API_KEY OPENSUBTITLES_API_KEY; do
  if [ -z "${!name:-}" ]; then
    value="$(from_container "$name")"
    if [ -n "$value" ]; then printf -v "$name" '%s' "$value"; fi
  fi
  if [ -n "${!name:-}" ]; then echo "==> $name: set"; else echo "==> $name: not set"; fi
done

# --- build ------------------------------------------------------------------------------------
echo "==> building seret-server:latest (a few minutes on the J4125)"
docker build -f Packages/SeretServer/Dockerfile -t seret-server:latest .

# --- recreate ---------------------------------------------------------------------------------
echo "==> recreating container"
docker rm -f seret-web >/dev/null 2>&1 || true
# Join the Letterboxd network so the server can reach the browser container by name at
# letterboxd-chromium:9223. Created here if it does not exist, so this stays a one-command deploy
# whether or not the browser has been set up yet — an absent browser only fails Letterboxd writes.
docker network create letterboxd-net >/dev/null 2>&1 || true

# `seret-web-data` keeps what the server learns across redeploys — above all each owned file's
# Hebrew-subtitle record, read once from Real-Debrid and otherwise re-read after every deploy.
docker run -d --name seret-web --restart unless-stopped \
  --network letterboxd-net \
  --device /dev/dri -p 8080:8080 \
  -v seret-web-data:/root/.local/share \
  -e RD_TOKEN="$RD" \
  -e TMDB_API_KEY="$TMDB_KEY" \
  ${OMDB_API_KEY:+-e OMDB_API_KEY="$OMDB_API_KEY"} \
  ${SERET_WEB_PASSWORD:+-e SERET_WEB_PASSWORD="$SERET_WEB_PASSWORD"} \
  ${OPENSUBTITLES_API_KEY:+-e OPENSUBTITLES_API_KEY="$OPENSUBTITLES_API_KEY"} \
  seret-server:latest >/dev/null

# --- verify -----------------------------------------------------------------------------------
echo "==> waiting for the server to come up"
for _ in $(seq 1 30); do
  if curl -fsS localhost:8080/health >/dev/null 2>&1; then
    echo "==> healthy"
    echo
    echo "    open http://192.168.1.179:8080/"
    echo "    (the library builds on the first request - give the grid a few moments to fill in)"
    exit 0
  fi
  sleep 2
done

echo "!! server did not become healthy - last logs:" >&2
docker logs --tail 20 seret-web >&2
exit 1
