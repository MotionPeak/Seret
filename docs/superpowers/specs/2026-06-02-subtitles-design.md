# Seret — Subtitles (SubtitleProvider + OpenSubtitlesProvider) — Design

**Status:** Draft for review
**Date:** 2026-06-02
**Owner:** Shahar Solomons
**Context:** Slice 2 of 3 of **Plan 6** ("finish the brain"): persistence ✓ → **subtitles** → `VideoPlayerEngine`. Realizes [`2026-06-02-seret-design.md`](2026-06-02-seret-design.md) §5.4. Built test-first in `DebridCore`; no UI.

---

## 1. Goal

On-demand **external** subtitles: a `SubtitleProvider` seam + an `OpenSubtitlesProvider` that searches OpenSubtitles for a movie/episode in given languages and **downloads a chosen subtitle to a ready-to-load temp file**. After this, the app (slice 3 / Plan 7) wires the player's "Search OpenSubtitles…" → pick → `engine.addExternalSubtitle(tempFileURL)`.

## 2. Scope

**In:** `SubtitleProvider` protocol + `SubtitleQuery` + `SubtitleResult` + `SubtitleError` + query builders; `OpenSubtitlesProvider` (actor: login/token-cache, search, download→temp file); a small `HTTPClient` extension (`post(json:)` + raw `data(_:)`).

**Out (deliberately):**
- **Embedded** subtitle/audio tracks (VLCKit enumerates them — the player's job, slice 3) and the actual `engine.addExternalSubtitle(url:)` call (slice 3 / app).
- A **Hebrew-specific** provider — future, slots in behind `SubtitleProvider` without touching the player.
- Any subtitle **persistence/caching** — downloaded on demand to a temp file.

## 3. Decisions (from brainstorming)

1. **`download(...)` returns a ready-to-load temp file URL.** The provider runs the whole flow (login → download request → fetch bytes → write temp file); the app/player stays dumb. All OpenSubtitles auth/quota complexity lives in the brain.
2. **Extend the shared `HTTPClient`** (a JSON-body POST + a raw-bytes GET) rather than a provider-local `URLSession` — one tested networking layer for RD/TMDB/OpenSubtitles.
3. **`OpenSubtitlesProvider` is an `actor`** — it caches the login JWT and coalesces re-login on `401`, mirroring `RealDebridSession`'s transparent-refresh pattern.

## 4. HTTPClient extension (`Networking/HTTPClient.swift`)

Today: `get<T: Decodable>(_:headers:)` and `post<T: Decodable>(_:form:headers:)` (form-urlencoded). Add:
- `func post<T: Decodable, Body: Encodable>(_ url: URL, json body: Body, headers: [String: String] = [:]) async throws -> T` — sets `Content-Type: application/json`, JSON-encodes `body`, decodes the response. (Login, download.)
- `func data(_ url: URL, headers: [String: String] = [:]) async throws -> Data` — GET returning raw bytes; same transport/status error mapping as `send`, **no** JSON decode. (Fetch the subtitle file.)

Both reuse the existing `send`-style error mapping (`HTTPError.transport`/`.status`/`.decoding`).

## 5. Components (`DebridCore/Subtitles/`)

### 5.1 `SubtitleProvider` (protocol, `Sendable`)
```
func search(_ query: SubtitleQuery, languages: [String]) async throws -> [SubtitleResult]
func download(_ result: SubtitleResult) async throws -> URL   // a local temp file
```

### 5.2 `SubtitleQuery` (`Sendable` value type)
`tmdbID: Int?`, `title: String`, `year: Int?`, `season: Int?`, `episode: Int?`. Convenience builders keep the provider decoupled from the library model while being ergonomic:
- `static func movie(_ item: MediaItem) -> SubtitleQuery` — `tmdbID`/`title`/`year`.
- `static func episode(show: MediaItem, episode: Episode) -> SubtitleQuery` — `show.tmdbID`/`show.title`/`year` + `episode.season`/`episode.number`.

(No `imdbID` — the domain only ever carries TMDB ids; OpenSubtitles search accepts `tmdb_id` directly. YAGNI.)

### 5.3 `SubtitleResult` (`Sendable` value type)
`fileID: Int`, `language: String`, `release: String?`, `fileName: String?`, `downloadCount: Int?`. `fileID` is the OpenSubtitles `attributes.files[0].file_id` of a search hit — the token `download` needs.

### 5.4 `OpenSubtitlesProvider` (`actor`) : `SubtitleProvider`
- `init(apiKey: String, credentials: Credentials, http: HTTPClient = HTTPClient(), userAgent: String = "Seret v1")`; `Credentials = (username: String, password: String)`.
- Base `https://api.opensubtitles.com/api/v1`. Every request carries `Api-Key` + `User-Agent` (OpenSubtitles rejects requests with no UA); POSTs add `Content-Type: application/json`; `download` adds `Authorization: Bearer <token>`.
- **`search`** → `GET /subtitles` with query items (`query` *or* `tmdb_id`; `languages` as a csv like `he,en`; `season_number`/`episode_number` for shows) → decode `{ data: [ { attributes: { language, release, download_count, files: [ { file_id, file_name } ] } } ] }` → `[SubtitleResult]`.
- **`download`** → ensure a token (lazy `login`, cached; re-login once on `401`) → `POST /download { file_id }` → `{ link, remaining, reset_time, … }` → if capped (`remaining <= 0`, or `403`/`406`) throw `.dailyCapReached(resetTime:)` → `http.data(link)` → write a temp file (extension from `file_name`, default `.srt`) → return the file URL.
- **`login`** (private) → `POST /login { username, password }` → `{ token }` → cache. The actor serializes access and coalesces concurrent logins.

### 5.5 `SubtitleError`
`.dailyCapReached(resetTime: Date?)`, `.notAuthenticated`. Transport/status/decoding surface as the existing `HTTPError`.

## 6. Key flow

Player "Search OpenSubtitles…" → build a `SubtitleQuery` from the playing `MediaItem` (movie) or `show + Episode` → `search(query, languages: ["he", "en"])` → user picks a `SubtitleResult` → `download(result)` → temp file URL → **(slice 3 / app)** `engine.addExternalSubtitle(url:)`. No results → empty array (not an error).

## 7. Error / cap handling

- **Daily cap** (`remaining <= 0` or `403`/`406`) → `SubtitleError.dailyCapReached(resetTime:)` so the app can say "limit reached, resets at X."
- **Bad credentials / login failure** → `.notAuthenticated` (or the underlying `HTTPError.status`).
- **`401` on download** → re-login once and retry; persistent failure surfaces.
- **Network / decode** → `HTTPError`. **Temp-file write failure** → throws.
- **Never log** the Api-Key, the login token, or download links.

## 8. Testing (test-first; Swift Testing; network suites nest under the serialized `MockTests`)

- **`HTTPClient`:** `post(json:)` encodes a JSON body and decodes the response (mock); `data(_:)` returns the raw bytes (mock).
- **`OpenSubtitlesProvider.search`:** mocked `/subtitles` → parses `language`/`fileID`/`release`.
- **`download` happy path:** mocked `login` → `download` → file fetch → **asserts the temp file exists and holds the fetched bytes**, and the returned URL is a local file.
- **Token caching:** two `download`s → `login` runs once (behavioral assertion via the routing mock — e.g. a 2nd login route that would fail/return a different token is never used).
- **`401` → re-login once** then succeed.
- **Daily cap:** `download` response with `remaining: 0` (or `403`) → throws `.dailyCapReached`.
- **Query builders:** movie/episode → correct `tmdbID`/`season`/`episode` fields.

## 9. Secrets

OpenSubtitles needs an **Api-Key** + a **user account** (username/password) — app-wiring (Plan 7) via the gitignored `Secrets.xcconfig`; **mocked in tests** (no real key needed). Per §10/§11 of the main spec.

## 10. Open questions for the plan

- Temp-file **location** (`FileManager.default.temporaryDirectory`) + **naming** (sanitized `file_name`, else `UUID` + extension) + **cleanup** (rely on OS temp cleanup for v1).
- Whether `download` returns just the `URL` or a small struct (URL + chosen language) — favor the simplest the player needs (URL).
- The exact **token-caching test** mechanism (behavioral, via the routing mock).

## 11. Spec reconciliation

Realizes §5.4 as written (no change needed). Minor: the protocol reads `search(_ query:languages:)` / `download(_:)` (the spec sketched `search(for:languages:)` — same intent).
