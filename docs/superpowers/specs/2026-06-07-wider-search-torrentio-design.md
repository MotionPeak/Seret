# Wider Search — Torrentio source (DMM-level coverage) — Design

**Date:** 2026-06-07
**Branch:** `feat/stage2-search-add`
**Builds on:** Stage 2 search/add + Request Download + Show all versions.

## Problem

Comet/elfhosted's index doesn't have brand-new titles' releases. A live probe of
`tt37287335` (Obsession 2026) returned 31 streams — the 1991 film, the 2023 TV series,
Spanish same-named films, a cinema DCP reel, and one 0.4 GB fake — **but not the real
2026 CAM**. DMM shows those CAMs because it pulls from a broader index. Seret needs the
same breadth.

## Spike result (2026-06-07) — PASS ✅

`GET https://torrentio.strem.fun/stream/movie/tt37287335.json` (free, public, no auth)
returned the real releases with high seeders:
- `Obsession.2026.1080p.TELESYNC.x264-UNiON` — 5446 seeders, 5.34 GB
- `Obsession - CAM 2026 1080P` ×2 — 1169 / 862 seeders
- `Obsession.2026.1080p.CAM.x264-DKS` — the exact DMM release

Stream shape is **the same as Comet's**: `{ name, title, infoHash (plaintext 40-hex),
fileIdx, behaviorHints.filename }`. Size + seeders live in the `title` text
(`💾 5.34 GB`, `👤 5446`). No debrid/cache info — Torrentio returns raw torrents.

Zilean (the literal DMM hashlist indexer) was rejected: the public elfhosted instance is
paywalled ("subscription state"). Torrentio is the free drop-in.

## Decisions

- **Add `TorrentioStreamSource`** (DebridCore) conforming to the existing `StreamSource`.
  Tokenless. Maps Torrentio streams → `CachedStream` with `isCached = false` (Torrentio
  can't confirm RD-instant availability). Parses size from the title text.
- **Cached-only path returns `[]`.** Torrentio can't guarantee instant availability, so it
  contributes only to the uncached path (Show all versions / Request Download). The one-tap
  **Play** (instant) path stays Comet-only and accurate.
- **Aggregate, don't replace.** New `AggregateStreamSource` queries its children
  concurrently and merges, deduping by infoHash (prefer a `isCached:true` variant so the
  badge stays accurate). `AppSession` wires `AggregateStreamSource([Comet, Torrentio])`.
- **Same gate.** Torrentio results pass the same `ReleaseMatcher` filter (title/year/isTV),
  so the 2023 series / wrong-year / wrong-film junk is still excluded.

## Architecture

```
AggregateStreamSource (StreamSource)
 ├─ CometStreamSource     cached-only → instant streams (⚡)   ; uncached → its index + cache flags
 └─ TorrentioStreamSource cached-only → []                    ; uncached → broad torrents (⬇️)
        merge by infoHash (prefer cached) → ReleaseMatcher-gated [CachedStream]
```

Everything downstream is unchanged: ranking, "Show all versions", per-version play
(instant) / download (uncached), the `DownloadStore` lifecycle. The breadth simply flows
into the existing list. A high-seeder uncached pick downloads fast on RD even when not
pre-cached.

## Components (each TDD, pure/mocked)

- `TorrentioStreamSource` — fetch + map + gate; size-from-title parser; movie + series ids.
- `AggregateStreamSource` — concurrent fan-out, flatten, dedupe-by-infoHash, prefer cached.
- `AppSession` — compose the aggregate as the app's `streamSource`.

## Testing

- `TorrentioStreamSource`: maps the real wire shape (mocked), gates out series/wrong-year,
  cached-only returns [], parses size, builds the series id `imdb:s:e`.
- `AggregateStreamSource`: merges two fakes, dedupes a shared infoHash preferring cached,
  surfaces a source's failure as empty (degrades, doesn't throw the whole query).
- On-device: real Obsession 2026 CAM now appears + fetches — owner-pending (live RD token).
