# Seret Stage 2 (Search → Instant RD Add) — Session Handoff (2026-06-07)

Resume guide for **Stage 2**: in-app search → add an already-cached torrent to Real-Debrid → play.
Read this + `CLAUDE.md` + the memory file `project_seret_stage2.md` to pick up exactly where this left off.

---

## TL;DR

- **Goal:** search a movie/TV title in Seret → get the best **already-cached** RD torrent added (**original-language audio first, then highest quality**) → play. Replaces DMM.
- **Engine decision:** **Comet** Stremio addon (public `https://comet.elfhosted.com`) behind a swappable `StreamSource` seam (MediaFusion is a drop-in). Comet does indexing **and** the RD cache-check (`cachedOnly:true`); RD's own `instantAvailability` is gone.
- **✅ Slice A (brain/engine) DONE, green, committed** — DebridCore **169 tests** (138→169), zero warnings.
- **📝 Slice B (DebridUI stores) PLAN written + committed; NOT executed** — blocked on the current branch's base (see Blocker).
- **Branch:** `feat/stage2-search-add`. **Nothing pushed. Nothing merged.**
- **Spec:** `docs/superpowers/specs/2026-06-07-seret-stage2-search-add-design.md`
- **Plans:** `docs/superpowers/plans/2026-06-07-seret-stage2-slice-a-engine.md` (done), `…-slice-b-debridui.md` (todo).

---

## What was built (Slice A — DebridCore, all TDD, all green)

10 atomic commits (`eb0f035` → `7d0411d`), each `feat(core)`/`refactor(core)`:

- **`HTTPClient.postForm`** — void POST for RD's 204 endpoints.
- **RD write path on `TorrentsClient`:** `addMagnet(magnet:)→AddMagnetResponse`, `selectFiles(torrentID:files:)`, high-level **`add(magnetHash:maxPollAttempts:pollInterval:sleep:)→TorrentInfo`** (addMagnet→poll→selectFiles(all)→poll until `downloaded`; throws `RDAddError.notInstant` if not instantly cached). `sleep` injected for tests.
- **TMDB:** `originalLanguage` + `imdbID` on `TMDBMovieDetails` (direct) and `TMDBTVDetails` (via `append_to_response=external_ids`).
- **`LanguageDetector`** — flag emoji + language words → ISO 639-1.
- **Shared `releaseQualityRank(for: ParsedRelease)`** — extracted from `MediaSource` (DRY; `CachedStream` reuses it). Named `releaseQualityRank` (not `qualityRank`) to dodge the smoke-scaffolding `DebridCore` type that shadows the module name.
- **`StreamSource` seam** + `StreamQuery` (`.movie`/`.series(season:episode:)`) + `CachedStream` (infoHash, fileIdx, rawTitle, parsed, languages, sizeBytes, sourceName).
- **`[CachedStream].rankedFor(originalLanguage:)` / `.bestMatch(originalLanguage:)→(stream,isFallback)`** — original-language → quality → size; `isFallback` flags a non-original auto-pick.
- **`CometStreamSource`** — builds the base64 RD config (`cachedOnly:true`), fetches `/{cfg}/stream/{movie|series}/{id}.json`, parses **infohash+fileIdx out of the `/playback/{hash}/{entry}/{fileIdx}/…` URL** (cached streams carry NO `infoHash`/`fileIdx` fields), quality via `FilenameParser`, languages via `LanguageDetector`. Fixture-tested.

## What's planned but NOT built

- **Slice B (DebridUI):** `SearchProviding`+`TMDBSearchService`, `SearchStore` (debounced TMDB search, merged best-first), `AddProviding`+`RealDebridAddService`, `AddStore` (loadStreams→bestMatch→addBest/add, states incl. `added(TorrentInfo)`/`addFailed`), `AppSession` wiring (`searchStore` + `makeAddStore(...)` factory). Full bite-sized plan committed.
- **Slice C (apps):** Search tab + results grid + Add screen (**Get best** · **Add & Play** · **More versions**) on SeretTV + SeretMobile; build `Add & Play`'s `PlaybackRequest` from the returned `TorrentInfo`; refresh library after add. Plan TBD.

---

## ⚠️ Blocker for Slice B (and the fix)

`swift test --package-path Shared/DebridUI` **fails to link on macOS** — `cannot link directly with 'SwiftUICore'` + undefined symbols — because the **mobile redesign added SwiftUI imports into DebridUI** (`Theme/Tokens.swift`, `Support/QRCode.swift`), and `feat/stage2-search-add` is based off the redesign HEAD. The DebridUI **library builds fine** (`swift build` OK); only the macOS test bundle won't link.

**Fix — base Slice B on `feat/mobile-foundation`** (no SwiftUI in DebridUI there → the original ~48 host-free tests link, `swift test` works). It's also the cleaner home for Stage 2. Alternative: run DebridUI tests via `xcodebuild test` on an iOS-sim destination.

## ⚠️ Shared-checkout gotcha

The owner + agent share ONE working tree. `git switch -c feat/stage2-search-add` moved the shared HEAD, so the **owner's parallel player commits landed on this branch** interleaved with Stage 2 (`8b75bf6`/`2488797 fix(player)`, `4ba4eb0 fix(mobile)`, …). Orthogonal and clearly labeled — Stage 2 commits are `feat(core)`/`refactor(core)`/`docs(...)`, the owner's are `fix(player)`/`fix(mobile)` — so they cherry-pick apart cleanly.

## ⚠️ Owner-pending verification (Slice A)

Task A10 Step 0 — capture **one** live Comet response with the owner's RD token to confirm the cached-stream wire format before fully trusting the decoder (the decoder + fixture are derived from reading Comet's GitHub source, not a live keyed call):
```bash
CFG=$(printf '{"debridService":"realdebrid","debridApiKey":"<RD_TOKEN>","cachedOnly":true,"resultFormat":["all"]}' | base64 | tr -d '\n')
curl -s "https://comet.elfhosted.com/${CFG}/stream/movie/tt0111161.json" | python3 -m json.tool | head -60
```
Confirm each stream has `url` containing `/playback/<40-hex>/`, a `name` with `⚡`, a multi-line `description`, and `behaviorHints.videoSize`. **Never commit/log the token.**

## Follow-up (minor)

`FilenameParser` returns `"BluRay"` for a `"BluRay.REMUX"` name (BluRay precedence) → real UHD remuxes rank as BluRay(tier 6) not REMUX(tier 7). Pre-existing; worth a fix in the shared parser.

---

## How to resume (next session)

```bash
cd /Users/shaharsolomons/Documents/Code/Seret
# 1) Branch Stage 2 off the clean base:
git switch feat/mobile-foundation
git switch -c feat/stage2            # the real Stage 2 home
# 2) Bring the Stage 2 commits over (skip the owner's fix(player)/fix(mobile)):
#    spec 9af28b1, Slice-A feat(core) eb0f035..7d0411d, the two plan docs.
git log --oneline feat/stage2-search-add   # to read the exact hashes
git cherry-pick <spec> <A1..A10> <planA> <planB>
# 3) Confirm the brain + DebridUI tests link here:
swift test --package-path Packages/DebridCore     # 169 green
swift test --package-path Shared/DebridUI         # links on this base
# 4) Execute Slice B per its plan, then write + execute Slice C.
```
(Adjust if the owner has merged the redesign by then — if redesign lands on main with the DebridUI SwiftUI import, prefer `xcodebuild test` on an iOS sim for DebridUI, or gate those imports behind `#if canImport(SwiftUI)`/move them out of the testable target.)
