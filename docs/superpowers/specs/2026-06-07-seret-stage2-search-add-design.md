# Seret Stage 2 — Search → Instant RD Add (design)

**Date:** 2026-06-07
**Status:** Approved — ready for implementation plan
**Milestone:** Stage 2 ("off DMM") — in-app search → Instant Real-Debrid Add flow.

## Goal

Let the user **search a movie or TV title inside Seret, get the best already-cached
version added to their Real-Debrid account, and play it** — replacing the DMM
(Debrid Media Manager) round-trip. "Best" means **audio in the title's original
language first, then highest quality**, and the add must be **instant** (the torrent
is already cached on RD, so RD resolves it to `downloaded` in seconds, not a
multi-hour download).

## Constraints / context

- **RD removed `instantAvailability`** — the old "is this torrent cached?" check is
  gone. RD still has `POST /torrents/addMagnet` + `POST /torrents/selectFiles/{id}`
  (the *add* endpoints), they're just not wrapped in `TorrentsClient` yet. The two
  hard parts RD no longer helps with are **(1) finding torrents for a title** and
  **(2) knowing which are already cached**.
- **Engine = a Stremio-protocol addon** (Comet by default; MediaFusion is a drop-in
  via the same seam). The addon does **both** hard parts in one call: indexing across
  many trackers **and** the RD-cache check (keyed by the user's RD token). It returns
  a ranked list of already-cached torrents with quality / language / size in each
  stream title.
- **One brain, three faces** (the repo's architectural rule): all search / parsing /
  ranking / RD-add logic lives in `DebridCore`; the addon sits behind a `StreamSource`
  seam; presentation lives in `DebridUI`; only UI lives in the app targets.
- **Privacy:** the addon needs the RD token in its config to check the *user's* cache.
  Token stays in Keychain on-device and is sent only to the addon (same trust model as
  using DMM today). The addon **base URL is a single configurable constant** so a
  self-hosted instance can replace the public one later without code changes.
- TDD throughout; zero warnings; Swift 6 strict concurrency; Swift Testing.

## Decisions (locked)

| Decision | Choice |
|---|---|
| Engine | **Comet** (Stremio addon) by default, behind a `StreamSource` seam; MediaFusion drop-in |
| Hosting | **Public ElfHosted instance** now; base URL is a configurable constant for self-host later |
| Scope | **Movies + TV shows** (episode/season aware) in the same milestone |
| Add UX | **Get best** (one tap, auto-pick) · **Add & Play** (add then play) · **More versions** (full ranked list to override) |
| Original-language fallback | **Never block** — if no original-language cached version exists, add the best-quality one anyway and **flag the audio** (`isFallback`) |

## The pipeline

```
TMDB search (movie/tv)
  → user picks a title
  → TMDB details: original_language + imdb_id   (append_to_response=external_ids)
  → StreamSource (Comet, RD-keyed): already-cached streams w/ quality·lang·size
  → rank: original-language audio first → quality → size
  → addMagnet(infoHash) + selectFiles(fileIdx) to RD   (instant: already cached)
  → torrent lands in the user's RD library
  → existing library refresh + play pipeline take over
```

## Components

### Brain — `DebridCore` (the engine)

1. **`StreamSource` seam** (protocol, `Sendable`):
   `func streams(for query: StreamQuery) async throws -> [CachedStream]`
   - `StreamQuery { imdbID: String, kind: Kind, originalLanguage: String? }`
     where `Kind = .movie | .series(season: Int, episode: Int)`.
   - `CachedStream { infoHash: String, fileIdx: Int?, rawTitle: String,
     parsed: ParsedRelease, languages: [String], sizeBytes: Int?, sourceName: String? }`.

2. **`CometStreamSource`** (impl of `StreamSource`):
   - Builds the Stremio stream URL: `{baseURL}/{rd-config}/stream/{movie|series}/{id}.json`
     where `id` is `tt1234567` (movie) or `tt1234567:S:E` (series).
   - Fetches via `HTTPClient`, decodes `{ streams: [...] }`.
   - Parses each stream's title with the existing `FilenameParser` (quality) and the new
     `LanguageDetector` (audio languages).
   - The RD-config segment encodes the user's RD token (the addon's config format).
   - **Exact instance URL + config encoding are verified at plan/research time** — this
     is a third-party, lightly-documented protocol, so the plan must confirm the wire
     format against a live instance before committing the constant.

3. **`LanguageDetector`** (pure): maps flag emoji (🇬🇧 🇫🇷 🇯🇵 …) and language words
   ("English", "French", "Hindi", "Japanese" …) found in a stream title to **ISO 639-1**
   codes. Used to match against TMDB `original_language`. Unit-tested in isolation.

4. **TMDB additions** (additive, back-compat):
   - `TMDBMovieDetails.originalLanguage` (`String`, ISO 639-1) + `imdbID` (`String?`).
   - `TMDBTVDetails.originalLanguage` + `imdbID` (via `append_to_response=external_ids`,
     since `/tv/{id}` doesn't return `imdb_id` directly).
   - Movie `imdb_id` comes back on `/movie/{id}` directly; both paths normalized to `imdbID`.

5. **Stream ranking** — `extension Array where Element == CachedStream`:
   `func rankedFor(originalLanguage: String?) -> [CachedStream]`
   sort key: **includes-original-language (desc)** → existing `qualityRank` (desc)
   → `sizeBytes` (desc). `best` = first element. A `CachedStream` (or a wrapping
   `RankedStream`) exposes `isFallback = (originalLanguage != nil && !includesOriginal)`
   so the UI can flag a non-original auto-pick.

6. **RD Add** — extend `TorrentsClient`:
   - `addMagnet(hash: String) async throws -> String` (returns RD torrent id) —
     `POST /torrents/addMagnet` (form `magnet=magnet:?xt=urn:btih:<hash>`).
   - `selectFiles(torrentID: String, fileIDs: [Int]) async throws` —
     `POST /torrents/selectFiles/{id}` (form `files=1,2` or `all`).
   - `add(stream: CachedStream) async throws -> TorrentInfo` (high-level):
     `addMagnet` → poll `info` → `selectFiles` (the `fileIdx`, else all video files) →
     return `TorrentInfo`. Cached ⇒ resolves to `downloaded` within a short timeout.
     If it does **not** go instant within the timeout (rare cache-miss race), surface a
     "still downloading — keep or remove?" outcome rather than silently leaving a slow
     torrent in the account.

### Shared presentation — `DebridUI`

7. **`SearchStore`** (`@Observable`): debounced TMDB query → `loading | empty | error |
   results([TMDBSearchResult])`. Cancellation-guarded like `LibraryStore`.

8. **`AddStore`** (`@Observable`): for a selected search result —
   fetch TMDB details (original_language + imdb_id) → `StreamSource.streams` →
   `rankedFor`. Exposes `best`, the full ranked list, and `isFallback`.
   Actions: `addBest()`, `add(stream:)`, `addAndPlay(stream:)`.
   Add-progress state: `idle | loadingStreams | streams(...) | noStreams | adding |
   added(TorrentInfo) | failed(error)`.

### Apps — `SeretTV` + `SeretMobile`

9. **Search tab**:
   - **SeretTV:** 4th tab in `LibraryShell` (`Tab("Search", systemImage:
     "magnifyingglass")`).
   - **SeretMobile:** a tab on iPhone (`TabView`) and a sidebar `Section.search` on iPad
     (`NavigationSplitView`).
10. **Search screen → results grid → Add screen.** The Add screen shows the title's
    poster/overview + **Get best** · **Add & Play** · **More versions** (expander listing
    the full ranked set, each with quality + language badges; the fallback pick is
    flagged). After add, the library refreshes; **Add & Play** builds the existing
    `PlaybackRequest` and pushes the existing player view.

## Error handling

- No cached streams for a title → empty state ("No cached versions found").
- Addon down / network error → error state with retry.
- Cache-miss race (added but not instant) → keep/remove prompt from `add(stream:)`.
- Invalid / expired RD token → existing auth/refresh path.
- TMDB result with no `imdb_id` → cannot query the addon; surface "can't search sources
  for this title" rather than crashing.

## Testing (TDD)

- `LanguageDetector`: flags + words → ISO codes; unknown → ignored. Pure, top-level suite.
- Ranking: original-language first, then quality, then size; `isFallback` correctness.
- `CometStreamSource`: `MockURLProtocol` on the addon JSON (nested under `MockTests`).
- `TorrentsClient.addMagnet`/`selectFiles`/`add`: `MockURLProtocol` (nested under `MockTests`).
- TMDB `originalLanguage` + `imdbID` decoding (movie direct, TV via external_ids).
- `SearchStore` / `AddStore`: fakes, host-free under `swift test` in `DebridUI`.

## Plan slices (for the implementation plan)

- **Slice A — brain/engine:** TMDB `originalLanguage`+`imdbID`; RD `addMagnet`/
  `selectFiles`/`add`; `StreamSource` seam + `CometStreamSource` + `LanguageDetector` +
  ranking. (Includes verifying the live Comet wire format before committing the URL/config.)
- **Slice B — DebridUI:** `SearchStore` + `AddStore` with all states + actions.
- **Slice C — apps:** Search tab + results grid + Add screen + Add & Play wiring, on
  both SeretTV and SeretMobile.

## Out of scope (Stage 2)

- Adding **un**cached torrents (waiting through an RD download) — Seret only adds
  instant/cached results.
- Wishlist / favorites / "notify when cached".
- Self-hosting setup UI (base URL stays a constant this milestone).
- Torrent search outside the addon (no direct tracker / Jackett integration).
