# Subtitles (SubtitleProvider + OpenSubtitlesProvider) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give `DebridCore` on-demand external subtitles — a `SubtitleProvider` seam and an `OpenSubtitlesProvider` that searches OpenSubtitles for a movie/episode in given languages and downloads a chosen subtitle to a ready-to-load temp file.

**Architecture:** Extend the shared `HTTPClient` with a JSON-body `post(json:)` and a raw-bytes `data(_:)`. Define the `SubtitleProvider` seam + value types + domain query-builders. Implement `OpenSubtitlesProvider` as an `actor` that caches the login JWT (coalesced re-login on `401`, like `RealDebridSession`), searches via `GET /subtitles`, and runs the full download flow (`POST /download` → fetch the link → write a temp file), surfacing the daily-download cap as a typed error.

**Tech Stack:** Swift 6.3 (Swift 6 language mode), SPM, async/await, actors, Swift Testing. No third-party deps; OpenSubtitles `api/v1` (Api-Key + login).

**Design spec:** [`docs/superpowers/specs/2026-06-02-subtitles-design.md`](../specs/2026-06-02-subtitles-design.md). Slice 2 of 3 of Plan 6 (persistence ✓ → subtitles → `VideoPlayerEngine`).

> **Conventions:** failing test → minimal impl → green → commit; small atomic `feat(core):`/`test(core):` commits. Swift 6 value types + `Sendable` (the provider is an `actor`); `public` API. **Zero warnings** (`swift build --package-path Packages/DebridCore 2>&1 | grep -i warning` prints nothing). Run the **full** suite before each commit. **Any suite touching `MockURLProtocol` MUST nest under the serialized `MockTests` parent**; pure suites stay plain top-level. **Never log** the Api-Key, login token, or download links. The mock handler must be `@Sendable`-safe — use `static` response builders and reassign `MockURLProtocol.handler` between sequential `await`s rather than capturing a mutable `var`.

**Baseline:** 84 tests green on `main`.

---

## OpenSubtitles API reference (what the code targets)

Base `https://api.opensubtitles.com/api/v1`. All requests send `Api-Key: <key>` + `User-Agent: <ua>`. JSON POSTs add `Content-Type: application/json`.
- `POST /login` body `{"username","password"}` → `{"token": "<jwt>", ...}`.
- `GET /subtitles?query=…|tmdb_id=…&languages=he,en&season_number=…&episode_number=…` → `{"data":[{"attributes":{"language","release","download_count","files":[{"file_id","file_name"}]}}]}`.
- `POST /download` body `{"file_id": N}` + `Authorization: Bearer <token>` → `{"link","file_name","remaining","reset_time_utc", …}`. `403`/`406` or `remaining <= 0` ⇒ daily cap.
- The `link` is a direct file URL — `GET` it for the raw subtitle bytes.

JSON uses snake_case; the package decoder is a plain `JSONDecoder()` (no key conversion), so wire models use explicit `CodingKeys` (matching `TMDBModels`).

---

## File Structure

| File | Responsibility |
|---|---|
| `Sources/DebridCore/Networking/HTTPClient.swift` (modify) | Add `post(_:json:headers:)` (JSON body) + `data(_:headers:)` (raw GET) |
| `Sources/DebridCore/Subtitles/SubtitleProvider.swift` | `SubtitleProvider` protocol + `SubtitleQuery` (+ builders) + `SubtitleResult` + `SubtitleError` |
| `Sources/DebridCore/Subtitles/OpenSubtitlesModels.swift` | Decode-only OpenSubtitles wire models (search + login + download) |
| `Sources/DebridCore/Subtitles/OpenSubtitlesProvider.swift` | The `actor`: search, login/token-cache, download→temp file, cap/401 handling |
| `Tests/DebridCoreTests/…` | One test file per piece (paths in each task) |

---

## Task 1: HTTPClient — JSON-body POST + raw-bytes GET

**Files:**
- Modify: `Packages/DebridCore/Sources/DebridCore/Networking/HTTPClient.swift`
- Create: `Packages/DebridCore/Tests/DebridCoreTests/HTTPClientJSONTests.swift`

- [ ] **Step 1: Write the failing test** (nested under `MockTests` — uses the mock transport)

`Tests/DebridCoreTests/HTTPClientJSONTests.swift`:
```swift
import Testing
import Foundation
@testable import DebridCore

extension MockTests {
    @Suite struct HTTPClientJSONTests {
        init() { MockURLProtocol.handler = nil }

        struct Echo: Codable, Equatable { let value: String }

        @Test func postJSONDecodesTheResponse() async throws {
            MockURLProtocol.stub(status: 200, json: #"{"value":"ok"}"#)
            let client = HTTPClient(session: .mock)
            let out: Echo = try await client.post(URL(string: "https://x/login")!, json: Echo(value: "hi"))
            #expect(out == Echo(value: "ok"))
        }

        @Test func dataReturnsRawBytes() async throws {
            MockURLProtocol.stub(status: 200, json: "SUBTITLE-BYTES")
            let client = HTTPClient(session: .mock)
            let bytes = try await client.data(URL(string: "https://x/file.srt")!)
            #expect(String(decoding: bytes, as: UTF8.self) == "SUBTITLE-BYTES")
        }

        @Test func dataThrowsOnNon2xx() async throws {
            MockURLProtocol.stub(status: 404, json: "nope")
            let client = HTTPClient(session: .mock)
            await #expect(throws: HTTPError.self) {
                _ = try await client.data(URL(string: "https://x/missing")!)
            }
        }
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path Packages/DebridCore --filter HTTPClientJSONTests`
Expected: FAIL to compile — `post(_:json:)` / `data(_:)` not defined.

- [ ] **Step 3: Implement the two methods**

In `Networking/HTTPClient.swift`, add inside `struct HTTPClient` (after the existing `post(_:form:headers:)`):
```swift
    public func post<T: Decodable, Body: Encodable>(_ url: URL, json body: Body,
                                                    headers: [String: String] = [:]) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw HTTPError.decoding(String(describing: error))
        }
        return try await send(request)
    }

    /// GET returning the raw response bytes (for non-JSON payloads like a subtitle file).
    public func data(_ url: URL, headers: [String: String] = [:]) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw HTTPError.transport(String(describing: error))
        }
        guard let http = response as? HTTPURLResponse else {
            throw HTTPError.transport("Non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw HTTPError.status(code: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }
        return data
    }
```
(`post(_:json:)` reuses the existing private `send`. `data(_:)` mirrors `send`'s transport/status mapping but skips the JSON decode. If the real `send`/`HTTPError` signatures differ, match them.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path Packages/DebridCore --filter HTTPClientJSONTests` → PASS (3). Then the full suite → **87 tests**. Zero warnings.

- [ ] **Step 5: Commit**

```bash
git add Packages/DebridCore
git commit -m "feat(core): HTTPClient JSON-body POST + raw-bytes GET"
```

---

## Task 2: SubtitleProvider seam + types + query builders

**Files:**
- Create: `Packages/DebridCore/Sources/DebridCore/Subtitles/SubtitleProvider.swift`
- Create: `Packages/DebridCore/Tests/DebridCoreTests/SubtitleQueryTests.swift`

- [ ] **Step 1: Write the failing test** (pure — plain top-level suite)

`Tests/DebridCoreTests/SubtitleQueryTests.swift`:
```swift
import Testing
import Foundation
@testable import DebridCore

@Suite struct SubtitleQueryTests {
    private func source(_ t: String) -> MediaSource {
        MediaSource(torrentID: "T", fileID: 1, restrictedLink: "https://rd/x", parsed: ParsedRelease(title: t))
    }

    @Test func movieQueryUsesTmdbTitleYear() {
        let item = MediaItem(id: "movie:tmdb:5", kind: .movie, title: "Dune", year: 2024,
                             sources: [source("Dune")], seasons: [], tmdbID: 5)
        let q = SubtitleQuery.movie(item)
        #expect(q.tmdbID == 5)
        #expect(q.title == "Dune")
        #expect(q.year == 2024)
        #expect(q.season == nil)
        #expect(q.episode == nil)
    }

    @Test func episodeQueryUsesShowTmdbAndEpisodeNumbers() {
        let ep = Episode(season: 2, number: 7, source: source("Show S02E07"))
        let show = MediaItem(id: "show:tmdb:9", kind: .show, title: "Show", year: 2011,
                             sources: [], seasons: [Season(number: 2, episodes: [ep])], tmdbID: 9)
        let q = SubtitleQuery.episode(show: show, episode: ep)
        #expect(q.tmdbID == 9)
        #expect(q.title == "Show")
        #expect(q.season == 2)
        #expect(q.episode == 7)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path Packages/DebridCore --filter SubtitleQueryTests`
Expected: FAIL to compile — `SubtitleQuery` undefined.

- [ ] **Step 3: Implement the seam + types**

`Sources/DebridCore/Subtitles/SubtitleProvider.swift`:
```swift
import Foundation

/// What to search subtitles for. Built from the domain types so callers don't construct it by hand;
/// `tmdbID` (when present) gives the best provider matches.
public struct SubtitleQuery: Sendable, Equatable {
    public var tmdbID: Int?
    public var title: String
    public var year: Int?
    public var season: Int?
    public var episode: Int?

    public init(tmdbID: Int? = nil, title: String, year: Int? = nil,
                season: Int? = nil, episode: Int? = nil) {
        self.tmdbID = tmdbID
        self.title = title
        self.year = year
        self.season = season
        self.episode = episode
    }

    public static func movie(_ item: MediaItem) -> SubtitleQuery {
        SubtitleQuery(tmdbID: item.tmdbID, title: item.title, year: item.year)
    }

    public static func episode(show: MediaItem, episode: Episode) -> SubtitleQuery {
        SubtitleQuery(tmdbID: show.tmdbID, title: show.title, year: show.year,
                      season: episode.season, episode: episode.number)
    }
}

/// One subtitle search hit. `fileID` is what `download` needs.
public struct SubtitleResult: Sendable, Equatable {
    public let fileID: Int
    public let language: String
    public let release: String?
    public let fileName: String?
    public let downloadCount: Int?

    public init(fileID: Int, language: String, release: String? = nil,
                fileName: String? = nil, downloadCount: Int? = nil) {
        self.fileID = fileID
        self.language = language
        self.release = release
        self.fileName = fileName
        self.downloadCount = downloadCount
    }
}

public enum SubtitleError: Error, Equatable, Sendable {
    /// The provider's daily download quota is exhausted; `resetTime` is when it refills, if known.
    case dailyCapReached(resetTime: Date?)
    /// Login failed / no valid session.
    case notAuthenticated
}

/// Finds and downloads external subtitles. A Hebrew-specific source can implement this later
/// without touching the player.
public protocol SubtitleProvider: Sendable {
    func search(_ query: SubtitleQuery, languages: [String]) async throws -> [SubtitleResult]
    /// Downloads the chosen subtitle to a local temp file and returns its URL.
    func download(_ result: SubtitleResult) async throws -> URL
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path Packages/DebridCore --filter SubtitleQueryTests` → PASS (2). Full suite → **89 tests**. Zero warnings.

- [ ] **Step 5: Commit**

```bash
git add Packages/DebridCore
git commit -m "feat(core): SubtitleProvider seam + SubtitleQuery/Result/Error + domain query builders"
```

---

## Task 3: OpenSubtitlesProvider — search

**Files:**
- Create: `Packages/DebridCore/Sources/DebridCore/Subtitles/OpenSubtitlesModels.swift`
- Create: `Packages/DebridCore/Sources/DebridCore/Subtitles/OpenSubtitlesProvider.swift`
- Create: `Packages/DebridCore/Tests/DebridCoreTests/OpenSubtitlesSearchTests.swift`

- [ ] **Step 1: Write the failing test** (nested under `MockTests`)

`Tests/DebridCoreTests/OpenSubtitlesSearchTests.swift`:
```swift
import Testing
import Foundation
@testable import DebridCore

extension MockTests {
    @Suite struct OpenSubtitlesSearchTests {
        init() { MockURLProtocol.handler = nil }

        private func provider() -> OpenSubtitlesProvider {
            OpenSubtitlesProvider(apiKey: "K",
                                  credentials: .init(username: "u", password: "p"),
                                  http: HTTPClient(session: .mock))
        }

        @Test func searchParsesResults() async throws {
            MockURLProtocol.stub(status: 200, json: #"""
            {"data":[{"attributes":{"language":"he","release":"Dune.2024","download_count":42,
              "files":[{"file_id":777,"file_name":"Dune.he.srt"}]}}]}
            """#)
            let results = try await provider().search(SubtitleQuery(tmdbID: 693134, title: "Dune"),
                                                      languages: ["he", "en"])
            #expect(results.count == 1)
            #expect(results[0].fileID == 777)
            #expect(results[0].language == "he")
            #expect(results[0].release == "Dune.2024")
            #expect(results[0].fileName == "Dune.he.srt")
            #expect(results[0].downloadCount == 42)
        }

        @Test func searchSkipsHitsWithNoFiles() async throws {
            MockURLProtocol.stub(status: 200, json: #"{"data":[{"attributes":{"language":"en","files":[]}}]}"#)
            let results = try await provider().search(SubtitleQuery(title: "x"), languages: [])
            #expect(results.isEmpty)
        }
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path Packages/DebridCore --filter OpenSubtitlesSearchTests`
Expected: FAIL to compile — `OpenSubtitlesProvider` undefined.

- [ ] **Step 3: Implement the wire models + the actor's search**

`Sources/DebridCore/Subtitles/OpenSubtitlesModels.swift`:
```swift
import Foundation

// Decode-only wire models for OpenSubtitles api/v1. snake_case → CodingKeys (the package
// decoder does no key conversion, matching TMDBModels).

struct OSSearchResponse: Decodable {
    let data: [OSSubtitle]
}

struct OSSubtitle: Decodable {
    let attributes: OSAttributes
}

struct OSAttributes: Decodable {
    let language: String?
    let release: String?
    let downloadCount: Int?
    let files: [OSFile]

    enum CodingKeys: String, CodingKey {
        case language, release, files
        case downloadCount = "download_count"
    }
}

struct OSFile: Decodable {
    let fileID: Int
    let fileName: String?

    enum CodingKeys: String, CodingKey {
        case fileID = "file_id"
        case fileName = "file_name"
    }
}

struct OSLoginResponse: Decodable {
    let token: String
}

struct OSDownloadResponse: Decodable {
    let link: String
    let fileName: String?
    let remaining: Int?
    let resetTimeUTC: String?

    enum CodingKeys: String, CodingKey {
        case link, remaining
        case fileName = "file_name"
        case resetTimeUTC = "reset_time_utc"
    }
}
```

`Sources/DebridCore/Subtitles/OpenSubtitlesProvider.swift`:
```swift
import Foundation

/// OpenSubtitles (api/v1) subtitle provider. An `actor` because it caches the login JWT.
/// `search` needs only the Api-Key; `download` (Task 4) needs a logged-in Bearer token.
public actor OpenSubtitlesProvider: SubtitleProvider {
    public struct Credentials: Sendable {
        public let username: String
        public let password: String
        public init(username: String, password: String) {
            self.username = username
            self.password = password
        }
    }

    public static let base = URL(string: "https://api.opensubtitles.com/api/v1")!

    private let apiKey: String
    private let credentials: Credentials
    private let http: HTTPClient
    private let userAgent: String
    private var token: String?

    public init(apiKey: String, credentials: Credentials,
                http: HTTPClient = HTTPClient(), userAgent: String = "Seret v1") {
        self.apiKey = apiKey
        self.credentials = credentials
        self.http = http
        self.userAgent = userAgent
    }

    private var baseHeaders: [String: String] { ["Api-Key": apiKey, "User-Agent": userAgent] }

    public func search(_ query: SubtitleQuery, languages: [String]) async throws -> [SubtitleResult] {
        var items: [URLQueryItem] = []
        if let id = query.tmdbID {
            items.append(URLQueryItem(name: "tmdb_id", value: String(id)))
        } else {
            items.append(URLQueryItem(name: "query", value: query.title))
        }
        if !languages.isEmpty {
            items.append(URLQueryItem(name: "languages", value: languages.joined(separator: ",")))
        }
        if let s = query.season { items.append(URLQueryItem(name: "season_number", value: String(s))) }
        if let e = query.episode { items.append(URLQueryItem(name: "episode_number", value: String(e))) }

        var comps = URLComponents(url: Self.base.appending(path: "subtitles"), resolvingAgainstBaseURL: false)!
        comps.queryItems = items
        let response: OSSearchResponse = try await http.get(comps.url!, headers: baseHeaders)
        return response.data.compactMap { sub in
            guard let file = sub.attributes.files.first else { return nil }
            return SubtitleResult(fileID: file.fileID,
                                  language: sub.attributes.language ?? "",
                                  release: sub.attributes.release,
                                  fileName: file.fileName,
                                  downloadCount: sub.attributes.downloadCount)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path Packages/DebridCore --filter OpenSubtitlesSearchTests` → PASS (2). Full suite → **91 tests**. Zero warnings.

- [ ] **Step 5: Commit**

```bash
git add Packages/DebridCore
git commit -m "feat(core): OpenSubtitlesProvider search + OpenSubtitles wire models"
```

---

## Task 4: OpenSubtitlesProvider — download (login + token cache + temp file)

**Files:**
- Modify: `Packages/DebridCore/Sources/DebridCore/Subtitles/OpenSubtitlesProvider.swift`
- Create: `Packages/DebridCore/Tests/DebridCoreTests/OpenSubtitlesDownloadTests.swift`

- [ ] **Step 1: Write the failing test** (nested under `MockTests`; routes RD-style by URL; static builders + handler reassignment between the two sequential downloads)

`Tests/DebridCoreTests/OpenSubtitlesDownloadTests.swift`:
```swift
import Testing
import Foundation
@testable import DebridCore

extension MockTests {
    @Suite struct OpenSubtitlesDownloadTests {
        init() { MockURLProtocol.handler = nil }

        private func provider() -> OpenSubtitlesProvider {
            OpenSubtitlesProvider(apiKey: "K",
                                  credentials: .init(username: "u", password: "p"),
                                  http: HTTPClient(session: .mock))
        }
        private func result(_ id: Int) -> SubtitleResult {
            SubtitleResult(fileID: id, language: "he")
        }
        private static func resp(_ req: URLRequest, _ status: Int, _ body: String) -> (HTTPURLResponse, Data) {
            (HTTPURLResponse(url: req.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }

        @Test func downloadWritesTempFileWithBytes() async throws {
            MockURLProtocol.handler = { req in
                let url = req.url!.absoluteString
                if url.contains("/login")    { return Self.resp(req, 200, #"{"token":"T1"}"#) }
                if url.contains("/download") { return Self.resp(req, 200, #"{"link":"https://cdn.example/x.srt","file_name":"x.srt","remaining":10}"#) }
                if url.contains("cdn.example/x.srt") { return Self.resp(req, 200, "SUBTITLE-CONTENT") }
                return Self.resp(req, 200, "{}")
            }
            let url = try await provider().download(result(1))
            #expect(url.isFileURL)
            #expect(try String(contentsOf: url, encoding: .utf8) == "SUBTITLE-CONTENT")
        }

        @Test func tokenIsCachedAcrossDownloads() async throws {
            let p = provider()
            MockURLProtocol.handler = { req in   // 1st download: login succeeds, token cached
                let url = req.url!.absoluteString
                if url.contains("/login")    { return Self.resp(req, 200, #"{"token":"T1"}"#) }
                if url.contains("/download") { return Self.resp(req, 200, #"{"link":"https://cdn.example/a.srt","remaining":10}"#) }
                if url.contains("cdn.example/a.srt") { return Self.resp(req, 200, "A") }
                return Self.resp(req, 200, "{}")
            }
            _ = try await p.download(result(1))
            // 2nd download: /login now 500s. If the token weren't cached, re-login would fail the call.
            MockURLProtocol.handler = { req in
                let url = req.url!.absoluteString
                if url.contains("/login")    { return Self.resp(req, 500, "{}") }
                if url.contains("/download") { return Self.resp(req, 200, #"{"link":"https://cdn.example/b.srt","remaining":9}"#) }
                if url.contains("cdn.example/b.srt") { return Self.resp(req, 200, "B") }
                return Self.resp(req, 200, "{}")
            }
            let url = try await p.download(result(2))
            #expect(try String(contentsOf: url, encoding: .utf8) == "B")   // succeeded ⇒ cached token, no re-login
        }
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path Packages/DebridCore --filter OpenSubtitlesDownloadTests`
Expected: FAIL to compile — `download` not defined.

- [ ] **Step 3: Implement download + login + temp-file (no cap/401 handling yet — Task 5)**

Add to `OpenSubtitlesProvider` (after `search`):
```swift
    public func download(_ result: SubtitleResult) async throws -> URL {
        let dl = try await requestDownload(fileID: result.fileID)
        guard let link = URL(string: dl.link) else { throw SubtitleError.notAuthenticated }
        let bytes = try await http.data(link)
        return try Self.writeTempFile(bytes, fileName: dl.fileName ?? result.fileName)
    }

    private func requestDownload(fileID: Int) async throws -> OSDownloadResponse {
        let token = try await ensureToken()
        return try await http.post(Self.base.appending(path: "download"),
                                   json: ["file_id": fileID], headers: authHeaders(token))
    }

    /// Returns the cached login token, logging in (once) if there isn't one.
    private func ensureToken() async throws -> String {
        if let token { return token }
        let response: OSLoginResponse = try await http.post(
            Self.base.appending(path: "login"),
            json: ["username": credentials.username, "password": credentials.password],
            headers: baseHeaders)
        token = response.token
        return response.token
    }

    private func authHeaders(_ token: String) -> [String: String] {
        var headers = baseHeaders
        headers["Authorization"] = "Bearer \(token)"
        return headers
    }

    /// Writes subtitle bytes to a temp file, returning the file URL. The name comes from the
    /// server's `file_name` (sanitized, `.srt` default) or a UUID fallback.
    static func writeTempFile(_ data: Data, fileName: String?) throws -> URL {
        let name = sanitizedFileName(fileName) ?? "\(UUID().uuidString).srt"
        let url = FileManager.default.temporaryDirectory.appending(path: name)
        try data.write(to: url, options: .atomic)
        return url
    }

    static func sanitizedFileName(_ name: String?) -> String? {
        guard let name, !name.isEmpty else { return nil }
        let safe = name.replacingOccurrences(of: "/", with: "_")
        return safe.contains(".") ? safe : safe + ".srt"
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path Packages/DebridCore --filter OpenSubtitlesDownloadTests` → PASS (2). Then the full suite → **93 tests**, run twice for concurrency stability. Zero warnings.

- [ ] **Step 5: Commit**

```bash
git add Packages/DebridCore
git commit -m "feat(core): OpenSubtitlesProvider download — login/token-cache + fetch to temp file"
```

---

## Task 5: OpenSubtitlesProvider — daily-cap + 401 re-login

**Files:**
- Modify: `Packages/DebridCore/Sources/DebridCore/Subtitles/OpenSubtitlesProvider.swift`
- Create: `Packages/DebridCore/Tests/DebridCoreTests/OpenSubtitlesRobustnessTests.swift`

- [ ] **Step 1: Write the failing tests** (nested under `MockTests`; the re-login test routes on the `Authorization` token value — no mutable capture)

`Tests/DebridCoreTests/OpenSubtitlesRobustnessTests.swift`:
```swift
import Testing
import Foundation
@testable import DebridCore

extension MockTests {
    @Suite struct OpenSubtitlesRobustnessTests {
        init() { MockURLProtocol.handler = nil }

        private func provider() -> OpenSubtitlesProvider {
            OpenSubtitlesProvider(apiKey: "K",
                                  credentials: .init(username: "u", password: "p"),
                                  http: HTTPClient(session: .mock))
        }
        private func result(_ id: Int) -> SubtitleResult { SubtitleResult(fileID: id, language: "he") }
        private static func resp(_ req: URLRequest, _ status: Int, _ body: String) -> (HTTPURLResponse, Data) {
            (HTTPURLResponse(url: req.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }

        @Test func dailyCapWhenRemainingZero() async throws {
            MockURLProtocol.handler = { req in
                let url = req.url!.absoluteString
                if url.contains("/login")    { return Self.resp(req, 200, #"{"token":"T1"}"#) }
                if url.contains("/download") { return Self.resp(req, 200, #"{"link":"https://cdn/x.srt","remaining":0,"reset_time_utc":"2026-06-03T00:00:00Z"}"#) }
                return Self.resp(req, 200, "{}")
            }
            await #expect(throws: SubtitleError.self) { _ = try await provider().download(result(1)) }
        }

        @Test func dailyCapWhenForbidden() async throws {
            MockURLProtocol.handler = { req in
                let url = req.url!.absoluteString
                if url.contains("/login")    { return Self.resp(req, 200, #"{"token":"T1"}"#) }
                if url.contains("/download") { return Self.resp(req, 403, "{}") }
                return Self.resp(req, 200, "{}")
            }
            await #expect(throws: SubtitleError.self) { _ = try await provider().download(result(1)) }
        }

        @Test func recoversFromExpiredTokenViaRelogin() async throws {
            let p = provider()
            // prime: cache token T1 with a successful download
            MockURLProtocol.handler = { req in
                let url = req.url!.absoluteString
                if url.contains("/login")    { return Self.resp(req, 200, #"{"token":"T1"}"#) }
                if url.contains("/download") { return Self.resp(req, 200, #"{"link":"https://cdn/a.srt","remaining":9}"#) }
                if url.contains("cdn/a.srt") { return Self.resp(req, 200, "A") }
                return Self.resp(req, 200, "{}")
            }
            _ = try await p.download(result(1))
            // T1 is now stale: a download bearing T1 → 401; re-login yields T2; T2 → 200.
            MockURLProtocol.handler = { req in
                let url = req.url!.absoluteString
                let auth = req.value(forHTTPHeaderField: "Authorization") ?? ""
                if url.contains("/login")    { return Self.resp(req, 200, #"{"token":"T2"}"#) }
                if url.contains("/download") {
                    return auth.contains("T2")
                        ? Self.resp(req, 200, #"{"link":"https://cdn/c.srt","remaining":5}"#)
                        : Self.resp(req, 401, "{}")
                }
                if url.contains("cdn/c.srt") { return Self.resp(req, 200, "C") }
                return Self.resp(req, 200, "{}")
            }
            let url = try await p.download(result(2))
            #expect(try String(contentsOf: url, encoding: .utf8) == "C")   // 401 → re-login → success
        }
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path Packages/DebridCore --filter OpenSubtitlesRobustnessTests`
Expected: FAIL — cap not detected (no throw) and the stale-token path 401s without recovering.

- [ ] **Step 3: Add cap detection + one-shot re-login**

Replace `requestDownload(fileID:)` in `OpenSubtitlesProvider` with:
```swift
    private func requestDownload(fileID: Int) async throws -> OSDownloadResponse {
        do {
            return try await attemptDownload(fileID: fileID)
        } catch let error as HTTPError {
            guard case .status(let code, _) = error else { throw error }
            switch code {
            case 401:
                token = nil                                   // expired → re-login once and retry
                return try await attemptDownload(fileID: fileID)
            case 403, 406:
                throw SubtitleError.dailyCapReached(resetTime: nil)
            default:
                throw error
            }
        }
    }

    private func attemptDownload(fileID: Int) async throws -> OSDownloadResponse {
        let token = try await ensureToken()
        let response: OSDownloadResponse = try await http.post(
            Self.base.appending(path: "download"),
            json: ["file_id": fileID], headers: authHeaders(token))
        if let remaining = response.remaining, remaining <= 0 {
            throw SubtitleError.dailyCapReached(resetTime: Self.parseResetTime(response.resetTimeUTC))
        }
        return response
    }

    static func parseResetTime(_ value: String?) -> Date? {
        guard let value else { return nil }
        return ISO8601DateFormatter().date(from: value)
    }
```
(The `catch` only handles `HTTPError`; `SubtitleError.dailyCapReached` thrown inside `attemptDownload` propagates untouched. The `401` retry calls `attemptDownload` once more — if it also fails, that error surfaces.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path Packages/DebridCore --filter OpenSubtitlesRobustnessTests` → PASS (3). Then the full suite → **96 tests**, run twice for stability. Zero warnings. Confirm `swift build … | grep -i warning` is empty.

- [ ] **Step 5: Commit**

```bash
git add Packages/DebridCore
git commit -m "feat(core): OpenSubtitlesProvider daily-cap error + one-shot 401 re-login"
```

---

## Done when

- [ ] `swift test --package-path Packages/DebridCore` green (**~96 tests**), stable across two runs, zero warnings.
- [ ] `DebridCore` exposes: `SubtitleProvider` (`search`/`download`), `SubtitleQuery` (+ `.movie`/`.episode` builders), `SubtitleResult`, `SubtitleError`, and `OpenSubtitlesProvider` (search + download-to-temp-file, login/token-cache, daily-cap + 401 re-login). `HTTPClient` gains `post(_:json:)` + `data(_:)`.
- [ ] Search prefers `tmdb_id`; download writes a real temp file holding the fetched bytes; the daily cap surfaces as `SubtitleError.dailyCapReached`.
- [ ] No Api-Key / token / link logged. All work committed (not pushed).

> **Consumer-side (slice 3 / app, NOT this slice):** the player's "Search OpenSubtitles…" UI, calling `engine.addExternalSubtitle(url:)` with the returned temp-file URL, and embedded-track enumeration. Secrets (OpenSubtitles Api-Key + account) are app-wiring (Plan 7); tests mock the transport.

**The flow, composed (app, slice 3):**
```swift
let provider = OpenSubtitlesProvider(apiKey: key, credentials: .init(username: u, password: p))
let hits = try await provider.search(.movie(item), languages: ["he", "en"])
let subURL = try await provider.download(hits[pick])
engine.addExternalSubtitle(url: subURL)
```

**Next:** Plan 6 slice 3 — the `VideoPlayerEngine` protocol (interface + playback model; concrete VLCKit engine ships with the app). Then Plan 7 — the Apple TV app.
