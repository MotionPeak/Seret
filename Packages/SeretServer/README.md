# SeretServer (Phase 0 skeleton)

A Vapor server that reuses the Swift **DebridCore** brain to list your Real-Debrid torrents and
play one in a browser — transcoded on the fly with ffmpeg + Intel QuickSync (VAAPI). This is the
walking skeleton that proves the spine; the real browse/watch product is Plan 2+.

Spec: `docs/superpowers/specs/2026-07-23-seret-web-server-design.md`
Plan: `docs/superpowers/plans/2026-07-23-seret-web-plan1-portability-skeleton.md`

## Endpoints
- `GET /` — lists your RD torrents as play links
- `GET /watch?id=<torrentID>` — transcodes + plays that torrent (hls.js)
- `GET /api/torrents` — JSON torrent list
- `POST /api/play?id=<torrentID>` — unrestrict → start transcode → `{mode,url,session}`
- `GET /hls/:session/**` — HLS manifest + segments
- `POST /api/play/:session/stop` — tear down a session
- `GET /health` — `ok`

## Config (env vars)
| Var | Required | Default | |
|---|---|---|---|
| `RD_TOKEN` | ✅ | — | real-debrid.com/apitoken |
| `SERET_PORT` | | 8080 | |
| `SERET_TRANSCODE_MAX_HEIGHT` | | 1080 | transcode cap |
| `SERET_MAX_SESSIONS` | | 2 | concurrent transcodes |
| `SERET_HLS_ROOT` | | /tmp/seret-hls | HLS scratch dir |

(`TMDB_API_KEY`, `SERET_WEB_PASSWORD` are read but unused in the skeleton — they arrive in Plan 2.)

## Run locally (macOS, no transcode HW)
```bash
RD_TOKEN=xxxx swift run --package-path Packages/SeretServer SeretServer
# open http://localhost:8080/ — the list works; playback needs ffmpeg+VAAPI (the container/NAS)
```

## Build the image
Build context is the **repo root** (for the DebridCore path dependency).

**On the NAS (recommended — native amd64, fast):** copy `Packages/` to the NAS and, via SSH or
Container Manager's build, run from the repo root:
```bash
docker build -f Packages/SeretServer/Dockerfile -t seret-server:latest .
```

**On an Apple-Silicon Mac (cross-build for the NAS, emulated → slow):**
```bash
docker buildx build --platform linux/amd64 -f Packages/SeretServer/Dockerfile \
  -t seret-server:latest --load .
docker save seret-server:latest -o /tmp/seret-server.tar   # import this tar in Container Manager
```

## Deploy on Synology (DS920+, Container Manager)
1. **Image → Add → Add from file** → the `seret-server.tar` (or build on the NAS).
2. **Container → Create** from `seret-server:latest`:
   - Port: host `8080` → container `8080`
   - Environment: `RD_TOKEN=<token>` (+ optional caps)
   - **Device: add `/dev/dri`** (so ffmpeg can reach QuickSync)
   - Volume (optional): a folder → `/tmp/seret-hls`
3. Start it. Confirm QuickSync inside the container: `vainfo` should init the **iHD** driver and list
   HEVC decode + H.264 encode entrypoints.
4. Browse `http://<nas-ip>:8080/` (LAN) or `http://<nas-tailscale-ip>:8080/` (remote) → click a
   movie → it should transcode via QuickSync (low CPU, `ffmpeg` running) and play.

## Not in the skeleton (Plan 2+)
TMDB library/organization · direct-play detection · auth gate · subtitles · React UI · resume ·
shows · search/Add.
