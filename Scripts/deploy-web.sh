#!/usr/bin/env bash
# One-shot deploy for SeretServer on the Synology NAS.
#
#   cd ~/Seret && git pull && sudo bash Scripts/deploy-web.sh <TMDB_API_KEY>
#
# Recovers RD_TOKEN from the currently-running container so it never has to be retyped.
# Optional: SERET_WEB_PASSWORD=secret sudo -E bash Scripts/deploy-web.sh <TMDB_API_KEY>
set -euo pipefail

TMDB_KEY="${1:-${TMDB_API_KEY:-}}"
if [ -z "$TMDB_KEY" ]; then
  echo "usage: sudo bash Scripts/deploy-web.sh <TMDB_API_KEY>" >&2
  exit 1
fi

# --- recover the RD token from the existing container -----------------------------------------
RD="${RD_TOKEN:-}"
if [ -z "$RD" ]; then
  RD="$(docker inspect seret-web --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null \
        | sed -n 's/^RD_TOKEN=//p' | head -1 || true)"
fi
if [ -z "$RD" ] || [ "$RD" = "PASTE_YOUR_TOKEN" ]; then
  echo "!! Could not recover a usable RD_TOKEN from the running 'seret-web' container." >&2
  echo "   Re-run as: RD_TOKEN='<your-rd-token>' sudo -E bash Scripts/deploy-web.sh <TMDB_API_KEY>" >&2
  exit 1
fi
echo "==> recovered RD_TOKEN from the existing container (${#RD} chars)"

# --- build ------------------------------------------------------------------------------------
echo "==> building seret-server:latest (a few minutes on the J4125)"
docker build -f Packages/SeretServer/Dockerfile -t seret-server:latest .

# --- recreate ---------------------------------------------------------------------------------
echo "==> recreating container"
docker rm -f seret-web >/dev/null 2>&1 || true
docker run -d --name seret-web --restart unless-stopped \
  --device /dev/dri -p 8080:8080 \
  -e RD_TOKEN="$RD" \
  -e TMDB_API_KEY="$TMDB_KEY" \
  ${SERET_WEB_PASSWORD:+-e SERET_WEB_PASSWORD="$SERET_WEB_PASSWORD"} \
  seret-server:latest >/dev/null

# --- verify -----------------------------------------------------------------------------------
echo "==> waiting for the server to come up"
for _ in $(seq 1 30); do
  if curl -fsS localhost:8080/health >/dev/null 2>&1; then
    echo "==> healthy"
    COUNT="$(curl -fsS localhost:8080/api/library 2>/dev/null | grep -o '"id"' | wc -l | tr -d ' ')"
    echo "==> /api/library returned ${COUNT:-0} titles"
    echo
    echo "    open http://192.168.1.179:8080/"
    exit 0
  fi
  sleep 2
done

echo "!! server did not become healthy - last logs:" >&2
docker logs --tail 20 seret-web >&2
exit 1
