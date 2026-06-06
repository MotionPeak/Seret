# Seret Stage 2 — Slice A (Brain / Engine) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `DebridCore` engine for "search → instant Real-Debrid Add": find already-cached torrents for a title via the Comet Stremio addon, rank them by original-language audio then quality, and add the pick to the user's RD account.

**Architecture:** Pure-Swift, UI-free additions to the `DebridCore` package only. A `StreamSource` seam abstracts the addon; `CometStreamSource` is the first impl. TMDB gains `originalLanguage`/`imdbID`. `TorrentsClient` gains the RD write path (`addMagnet`/`selectFiles`/high-level `add`). Quality ranking is shared with the existing library ranker; a new `LanguageDetector` maps flag emoji/words → ISO 639-1 for the original-language match.

**Tech Stack:** Swift 6.3 (strict concurrency), Swift Testing, `MockURLProtocol` for transport mocking. No third-party deps.

---

## Context the implementer needs (read before starting)

- **One brain, three faces:** ALL logic here lives in `DebridCore`. No UI, no VLCKit. App/UI wiring is Slices B & C (separate plans).
- **Comet wire format** (verified from g0ldyy/comet `main` + RD official docs, 2026-06-07):
  - Base URL: `https://comet.elfhosted.com`.
  - Config = **plain Base64** (NOT url-safe) of a JSON object, as the **first path segment**. Minimal config for our use:
    `{"debridService":"realdebrid","debridApiKey":"<RD_TOKEN>","cachedOnly":true,"resultFormat":["all"]}`.
  - Stream endpoint: `GET {base}/{b64config}/stream/{movie|series}/{id}.json`, where `id` = `tt1234567` (movie) or `tt1234567:S:E` (series, e.g. `tt0944947:1:2`).
  - Response: `{"streams":[ ... ]}`. **Cached debrid streams carry NO `infoHash`/`fileIdx` fields** — the infohash + file index are embedded in the `url` path: `…/playback/{infohash}/{entry}/{fileIndex}/{season}/{episode}` (fileIndex may be the literal `"n"` when unknown). `name` looks like `"[RD⚡] Comet 2160p"` (the `⚡` = cached). `description` is a multi-line block; line 1 is `📄 {torrent title}`; the language line is `/`-joined flag emojis (e.g. `🇺🇸/🇫🇷`). `behaviorHints.videoSize` carries the byte size.
  - `cachedOnly:true` guarantees the response only contains instantly-cached results.
  - ⚠️ ElfHosted blocks debrid-less configs; a real RD token is required to get results.
- **RD write endpoints** (auth header `Authorization: Bearer <token>`, **form-urlencoded** bodies):
  - `POST /torrents/addMagnet` — form `magnet=magnet:?xt=urn:btih:<hash>` → **201** `{"id":"<id>","uri":"..."}`.
  - `POST /torrents/selectFiles/{id}` — form `files=all` (or `1,2,3`) → **204** (empty body).
  - `GET /torrents/info/{id}` → `status` (`downloaded` = ready), `files[]`, `links[]`.
  - `instantAvailability` is gone — never call it; rely on Comet's `cachedOnly`.
- **Test harness:** suites using `MockURLProtocol` MUST nest under the serialized `MockTests` parent: `extension MockTests { @Suite struct … { init() { MockURLProtocol.handler = nil } } }`. Construct clients with `HTTPClient(session: .mock)`. Stub with `MockURLProtocol.stub(status:json:)` for a single response, or set `MockURLProtocol.handler = { request in … }` directly for multi-call sequences. Pure suites (no network) stay plain top-level structs.
- **Run the full brain suite before declaring a task done:** `swift test --package-path Packages/DebridCore`. Zero-warning bar: `swift build --package-path Packages/DebridCore 2>&1 | grep -i warning` must print nothing.
- **Commit style:** `feat(core):` / `refactor(core):` / `test(core):`, small atomic commits per task.

## File structure (created/modified in this slice)

```
Packages/DebridCore/Sources/DebridCore/
  Networking/HTTPClient.swift                 (MODIFY: add postForm — void POST for 204s)
  Metadata/TMDBClient.swift                    (MODIFY: tvDetails append_to_response=external_ids)
  Metadata/TMDBModels.swift                    (MODIFY: originalLanguage + imdbID on movie/tv details)
  RealDebrid/RealDebridResourceModels.swift    (MODIFY: add AddMagnetResponse)
  RealDebrid/TorrentsClient.swift              (MODIFY: addMagnet, selectFiles, add(magnetHash:))
  RealDebrid/RDAddError.swift                  (CREATE)
  Library/QualityRank.swift                    (CREATE: shared qualityRank(for: ParsedRelease))
  Library/MediaSourceRanking.swift             (MODIFY: delegate to shared qualityRank)
  Search/StreamModels.swift                    (CREATE: StreamQuery, StreamKind, CachedStream)
  Search/StreamSource.swift                    (CREATE: StreamSource protocol)
  Search/CachedStreamRanking.swift             (CREATE: rankedFor / bestMatch)
  Search/LanguageDetector.swift                (CREATE)
  Search/CometStreamSource.swift               (CREATE)
Packages/DebridCore/Tests/DebridCoreTests/
  HTTPClientPostFormTests.swift                (CREATE)
  TMDBDetailsLanguageTests.swift               (CREATE)
  TorrentsAddTests.swift                        (CREATE)
  QualityRankTests.swift                        (CREATE)
  CachedStreamRankingTests.swift               (CREATE)
  LanguageDetectorTests.swift                  (CREATE)
  CometStreamSourceTests.swift                 (CREATE)
  Fixtures/comet-movie-cached.json             (CREATE: captured/representative response)
```

---

## Task A1: `HTTPClient.postForm` — void POST for 204 endpoints

RD's `selectFiles` returns **204 with an empty body**; the existing generic `post<T:Decodable>` would fail decoding empty data. Add a non-decoding form POST.

**Files:**
- Modify: `Packages/DebridCore/Sources/DebridCore/Networking/HTTPClient.swift`
- Test: `Packages/DebridCore/Tests/DebridCoreTests/HTTPClientPostFormTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import Foundation
@testable import DebridCore

extension MockTests {
    @Suite struct HTTPClientPostFormTests {
        init() { MockURLProtocol.handler = nil }

        @Test func postFormSucceedsOnEmpty204Body() async throws {
            MockURLProtocol.handler = { request in
                let body = request.bodyString()
                #expect(body.contains("files=all"))
                let response = HTTPURLResponse(url: request.url!, statusCode: 204,
                                               httpVersion: nil, headerFields: nil)!
                return (response, Data())
            }
            let client = HTTPClient(session: .mock)
            // Should NOT throw despite the empty body.
            try await client.postForm(URL(string: "https://example.com/x")!, form: ["files": "all"])
        }

        @Test func postFormThrowsOnErrorStatus() async throws {
            MockURLProtocol.stub(status: 400, json: #"{"error":"bad"}"#)
            let client = HTTPClient(session: .mock)
            await #expect(throws: HTTPError.self) {
                try await client.postForm(URL(string: "https://example.com/x")!, form: [:])
            }
        }
    }
}

/// Test helper: read a URLRequest's httpBody (or httpBodyStream) as a String.
extension URLRequest {
    func bodyString() -> String {
        if let body = httpBody { return String(decoding: body, as: UTF8.self) }
        guard let stream = httpBodyStream else { return "" }
        stream.open(); defer { stream.close() }
        var data = Data(); let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return String(decoding: data, as: UTF8.self)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/DebridCore --filter HTTPClientPostFormTests`
Expected: FAIL — `value of type 'HTTPClient' has no member 'postForm'`.

- [ ] **Step 3: Write minimal implementation**

Add to `HTTPClient` (after the `data(_:)` method):

```swift
    /// POSTs a form-urlencoded body and validates the status, discarding the response body.
    /// For endpoints that return 204 No Content (e.g. RD `selectFiles`).
    public func postForm(_ url: URL, form: [String: String], headers: [String: String] = [:]) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        request.httpBody = Data(Self.encodeForm(form).utf8)
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
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path Packages/DebridCore --filter HTTPClientPostFormTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Packages/DebridCore/Sources/DebridCore/Networking/HTTPClient.swift \
        Packages/DebridCore/Tests/DebridCoreTests/HTTPClientPostFormTests.swift
git commit -m "feat(core): add HTTPClient.postForm for 204 endpoints"
```

---

## Task A2: RD `addMagnet` + `AddMagnetResponse`

**Files:**
- Modify: `Packages/DebridCore/Sources/DebridCore/RealDebrid/RealDebridResourceModels.swift`
- Modify: `Packages/DebridCore/Sources/DebridCore/RealDebrid/TorrentsClient.swift`
- Test: `Packages/DebridCore/Tests/DebridCoreTests/TorrentsAddTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import Foundation
@testable import DebridCore

extension MockTests {
    @Suite struct TorrentsAddTests {
        init() { MockURLProtocol.handler = nil }

        struct StubTokens: AccessTokenProviding {
            func validAccessToken() async throws -> String { "TESTTOKEN" }
        }

        @Test func addMagnetReturnsTorrentID() async throws {
            MockURLProtocol.handler = { request in
                #expect(request.url?.path.hasSuffix("/torrents/addMagnet") == true)
                #expect(request.bodyString().contains("magnet"))
                let response = HTTPURLResponse(url: request.url!, statusCode: 201,
                                               httpVersion: nil, headerFields: nil)!
                return (response, Data(#"{"id":"NEWID","uri":"https://rd/t/NEWID"}"#.utf8))
            }
            let client = TorrentsClient(http: HTTPClient(session: .mock), tokens: StubTokens())
            let result = try await client.addMagnet(magnet: "magnet:?xt=urn:btih:abc")
            #expect(result.id == "NEWID")
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/DebridCore --filter TorrentsAddTests`
Expected: FAIL — no `AddMagnetResponse` / no `addMagnet`.

- [ ] **Step 3: Write minimal implementation**

Append to `RealDebridResourceModels.swift`:

```swift
/// Response from `POST /torrents/addMagnet` (also `addTorrent`).
public struct AddMagnetResponse: Decodable, Sendable, Equatable {
    public let id: String
    public let uri: String?

    public init(id: String, uri: String? = nil) {
        self.id = id; self.uri = uri
    }
}
```

Add to `TorrentsClient` (after `unrestrict(link:)`):

```swift
    /// Adds a magnet to the user's RD account. Returns the new torrent's id.
    /// `POST /torrents/addMagnet` (form `magnet`). RD returns 201.
    public func addMagnet(magnet: String) async throws -> AddMagnetResponse {
        try await http.post(Self.base.appending(path: "torrents/addMagnet"),
                            form: ["magnet": magnet],
                            headers: try await authHeaders())
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path Packages/DebridCore --filter TorrentsAddTests`
Expected: PASS (1 test).

- [ ] **Step 5: Commit**

```bash
git add Packages/DebridCore/Sources/DebridCore/RealDebrid/RealDebridResourceModels.swift \
        Packages/DebridCore/Sources/DebridCore/RealDebrid/TorrentsClient.swift \
        Packages/DebridCore/Tests/DebridCoreTests/TorrentsAddTests.swift
git commit -m "feat(core): add RD addMagnet"
```

---

## Task A3: RD `selectFiles`

**Files:**
- Modify: `Packages/DebridCore/Sources/DebridCore/RealDebrid/TorrentsClient.swift`
- Test: `Packages/DebridCore/Tests/DebridCoreTests/TorrentsAddTests.swift` (add to existing suite)

- [ ] **Step 1: Write the failing test**

Add this `@Test` inside the `TorrentsAddTests` suite:

```swift
        @Test func selectFilesPostsAllAndSucceedsOn204() async throws {
            MockURLProtocol.handler = { request in
                #expect(request.url?.path.contains("/torrents/selectFiles/NEWID") == true)
                #expect(request.bodyString().contains("files=all"))
                let response = HTTPURLResponse(url: request.url!, statusCode: 204,
                                               httpVersion: nil, headerFields: nil)!
                return (response, Data())
            }
            let client = TorrentsClient(http: HTTPClient(session: .mock), tokens: StubTokens())
            try await client.selectFiles(torrentID: "NEWID", files: "all")
        }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/DebridCore --filter TorrentsAddTests`
Expected: FAIL — no `selectFiles`.

- [ ] **Step 3: Write minimal implementation**

Add to `TorrentsClient` (after `addMagnet`):

```swift
    /// Selects which files of a torrent to download. `files` is RD's raw param:
    /// the literal `"all"` or a comma-separated list of file ids ("1,2,3").
    /// `POST /torrents/selectFiles/{id}` returns 204.
    public func selectFiles(torrentID: String, files: String) async throws {
        try await http.postForm(Self.base.appending(path: "torrents/selectFiles/\(torrentID)"),
                                form: ["files": files],
                                headers: try await authHeaders())
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path Packages/DebridCore --filter TorrentsAddTests`
Expected: PASS (2 tests now in the suite).

- [ ] **Step 5: Commit**

```bash
git add Packages/DebridCore/Sources/DebridCore/RealDebrid/TorrentsClient.swift \
        Packages/DebridCore/Tests/DebridCoreTests/TorrentsAddTests.swift
git commit -m "feat(core): add RD selectFiles"
```

---

## Task A4: RD high-level `add(magnetHash:)` + `RDAddError`

Chains addMagnet → poll until files are selectable → selectFiles(all) → poll until `downloaded` (instant for cached) → return `TorrentInfo`. `sleep` is injected so tests run instantly. If it doesn't reach `downloaded` within the attempt budget, throws `.notInstant` so the UI can offer keep/remove.

**Files:**
- Create: `Packages/DebridCore/Sources/DebridCore/RealDebrid/RDAddError.swift`
- Modify: `Packages/DebridCore/Sources/DebridCore/RealDebrid/TorrentsClient.swift`
- Test: `Packages/DebridCore/Tests/DebridCoreTests/TorrentsAddTests.swift`

- [ ] **Step 1: Write the failing test**

Add these `@Test`s inside `TorrentsAddTests`:

```swift
        // A stateful handler driving the add() sequence:
        // addMagnet → info(no files) → info(waiting_files_selection) → selectFiles → info(downloaded)
        @Test func addInstantCachedReturnsDownloadedInfo() async throws {
            let infoWaiting = #"{"id":"NEWID","filename":"M","hash":"h","bytes":1,"progress":0,"status":"waiting_files_selection","files":[{"id":1,"path":"/M/m.mkv","bytes":1,"selected":0}],"links":[]}"#
            let infoDone = #"{"id":"NEWID","filename":"M","hash":"h","bytes":1,"progress":100,"status":"downloaded","files":[{"id":1,"path":"/M/m.mkv","bytes":1,"selected":1}],"links":["https://rd/d/X"]}"#
            let counter = Counter()
            MockURLProtocol.handler = { request in
                let path = request.url?.path ?? ""
                let json: String
                if path.hasSuffix("/torrents/addMagnet") {
                    json = #"{"id":"NEWID","uri":"u"}"#
                } else if path.contains("/torrents/selectFiles/") {
                    let r = HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!
                    return (r, Data())
                } else { // /torrents/info/NEWID
                    json = counter.next() == 0 ? infoWaiting : infoDone
                }
                let r = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (r, Data(json.utf8))
            }
            let client = TorrentsClient(http: HTTPClient(session: .mock), tokens: StubTokens())
            let info = try await client.add(magnetHash: "abc", pollInterval: .zero, sleep: { _ in })
            #expect(info.status == "downloaded")
            #expect(info.id == "NEWID")
        }

        @Test func addThrowsNotInstantWhenNeverDownloaded() async throws {
            let infoDownloading = #"{"id":"NEWID","filename":"M","hash":"h","bytes":1,"progress":5,"status":"downloading","files":[{"id":1,"path":"/M/m.mkv","bytes":1,"selected":1}],"links":[]}"#
            MockURLProtocol.handler = { request in
                let path = request.url?.path ?? ""
                if path.hasSuffix("/torrents/addMagnet") {
                    let r = HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!
                    return (r, Data(#"{"id":"NEWID"}"#.utf8))
                }
                if path.contains("/torrents/selectFiles/") {
                    let r = HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!
                    return (r, Data())
                }
                let r = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (r, Data(infoDownloading.utf8))
            }
            let client = TorrentsClient(http: HTTPClient(session: .mock), tokens: StubTokens())
            await #expect(throws: RDAddError.self) {
                _ = try await client.add(magnetHash: "abc", maxPollAttempts: 3, pollInterval: .zero, sleep: { _ in })
            }
        }
    }
}

/// Thread-safe call counter for sequencing mock responses.
final class Counter: @unchecked Sendable {
    private let lock = NSLock(); private var n = 0
    func next() -> Int { lock.lock(); defer { lock.unlock() }; let v = n; n += 1; return v }
}
```

> Note: the closing `}` braces above end the `TorrentsAddTests` suite and the `MockTests` extension — make sure you don't double-close. `Counter` is top-level (outside the extension).

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/DebridCore --filter TorrentsAddTests`
Expected: FAIL — no `RDAddError`, no `add(magnetHash:…)`.

- [ ] **Step 3: Write minimal implementation**

Create `RDAddError.swift`:

```swift
import Foundation

/// Errors from the high-level RD add flow (`TorrentsClient.add`).
public enum RDAddError: Error, Equatable, Sendable {
    /// Added + selected, but it did not reach `downloaded` within the poll budget —
    /// it wasn't actually instantly cached. `torrentID` lets the caller remove it.
    case notInstant(torrentID: String)
    /// RD reported a terminal error status (e.g. "error", "magnet_error", "dead", "virus").
    case failed(status: String, torrentID: String)
}
```

Add to `TorrentsClient` (after `selectFiles`):

```swift
    /// Terminal RD failure statuses for the add flow.
    private static let errorStatuses: Set<String> = ["error", "magnet_error", "dead", "virus"]

    /// High-level add for an instantly-cached torrent: addMagnet → wait for file listing →
    /// selectFiles(all) → wait for `downloaded` → return its `TorrentInfo`. Because the torrent
    /// is already cached, RD resolves it in seconds. Throws `RDAddError.notInstant` if it does
    /// not reach `downloaded` within `maxPollAttempts`, or `.failed` on a terminal status.
    /// `sleep` is injected for testability (pass a no-op in tests).
    public func add(magnetHash: String,
                    maxPollAttempts: Int = 20,
                    pollInterval: Duration = .seconds(1),
                    sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) async throws -> TorrentInfo {
        let added = try await addMagnet(magnet: "magnet:?xt=urn:btih:\(magnetHash)")
        let id = added.id

        // 1) Wait until RD has listed files / is ready for selection.
        var info = try await self.info(id: id)
        var attempts = 0
        while info.files.isEmpty && info.status != "waiting_files_selection" && attempts < maxPollAttempts {
            if Self.errorStatuses.contains(info.status) { throw RDAddError.failed(status: info.status, torrentID: id) }
            try await sleep(pollInterval)
            info = try await self.info(id: id)
            attempts += 1
        }

        // 2) Select all files (cached pack → all episodes available; movie → the film).
        try await selectFiles(torrentID: id, files: "all")

        // 3) Wait for the cached torrent to flip to `downloaded`.
        info = try await self.info(id: id)
        attempts = 0
        while info.status != "downloaded" && attempts < maxPollAttempts {
            if Self.errorStatuses.contains(info.status) { throw RDAddError.failed(status: info.status, torrentID: id) }
            try await sleep(pollInterval)
            info = try await self.info(id: id)
            attempts += 1
        }
        guard info.status == "downloaded" else { throw RDAddError.notInstant(torrentID: id) }
        return info
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path Packages/DebridCore --filter TorrentsAddTests`
Expected: PASS (4 tests in the suite).

- [ ] **Step 5: Commit**

```bash
git add Packages/DebridCore/Sources/DebridCore/RealDebrid/RDAddError.swift \
        Packages/DebridCore/Sources/DebridCore/RealDebrid/TorrentsClient.swift \
        Packages/DebridCore/Tests/DebridCoreTests/TorrentsAddTests.swift
git commit -m "feat(core): add high-level RD add(magnetHash:) with instant-cache polling"
```

---

## Task A5: TMDB `originalLanguage` + `imdbID`

Movie details (`/movie/{id}`) return `original_language` + `imdb_id` directly. TV details (`/tv/{id}`) return `original_language` but NOT `imdb_id` — fetch it via `append_to_response=external_ids`.

**Files:**
- Modify: `Packages/DebridCore/Sources/DebridCore/Metadata/TMDBModels.swift`
- Modify: `Packages/DebridCore/Sources/DebridCore/Metadata/TMDBClient.swift`
- Test: `Packages/DebridCore/Tests/DebridCoreTests/TMDBDetailsLanguageTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import Foundation
@testable import DebridCore

extension MockTests {
    @Suite struct TMDBDetailsLanguageTests {
        init() { MockURLProtocol.handler = nil }

        @Test func movieDetailsDecodeOriginalLanguageAndImdbID() async throws {
            MockURLProtocol.stub(status: 200, json: #"""
            {"id":603,"title":"The Matrix","release_date":"1999-03-30","overview":"o",
             "poster_path":"/p.jpg","backdrop_path":"/b.jpg","runtime":136,"genres":[],
             "vote_average":8.2,"original_language":"en","imdb_id":"tt0133093"}
            """#)
            let client = TMDBClient(apiKey: "K", http: HTTPClient(session: .mock))
            let details = try await client.movieDetails(id: 603)
            #expect(details.originalLanguage == "en")
            #expect(details.imdbID == "tt0133093")
        }

        @Test func tvDetailsDecodeOriginalLanguageAndExternalImdbID() async throws {
            MockURLProtocol.handler = { request in
                // Verify we requested external_ids.
                #expect(request.url?.query?.contains("append_to_response=external_ids") == true)
                let json = #"""
                {"id":1399,"name":"Game of Thrones","first_air_date":"2011-04-17","overview":"o",
                 "poster_path":"/p.jpg","backdrop_path":"/b.jpg","number_of_seasons":8,"genres":[],
                 "vote_average":8.4,"original_language":"en",
                 "external_ids":{"imdb_id":"tt0944947"}}
                """#
                let r = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (r, Data(json.utf8))
            }
            let client = TMDBClient(apiKey: "K", http: HTTPClient(session: .mock))
            let details = try await client.tvDetails(id: 1399)
            #expect(details.originalLanguage == "en")
            #expect(details.imdbID == "tt0944947")
        }

        @Test func tvDetailsToleratesMissingExternalIDs() async throws {
            MockURLProtocol.stub(status: 200, json: #"""
            {"id":1,"name":"X","first_air_date":null,"overview":null,"poster_path":null,
             "backdrop_path":null,"number_of_seasons":null,"genres":[],"vote_average":null,
             "original_language":"ja"}
            """#)
            let client = TMDBClient(apiKey: "K", http: HTTPClient(session: .mock))
            let details = try await client.tvDetails(id: 1)
            #expect(details.originalLanguage == "ja")
            #expect(details.imdbID == nil)
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/DebridCore --filter TMDBDetailsLanguageTests`
Expected: FAIL — `originalLanguage`/`imdbID` not members.

- [ ] **Step 3: Write minimal implementation**

In `TMDBModels.swift`, replace `TMDBMovieDetails` with (adds two fields + CodingKeys + init params):

```swift
public struct TMDBMovieDetails: Decodable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let title: String
    public let releaseDate: String?
    public let overview: String?
    public let posterPath: String?
    public let backdropPath: String?
    public let runtime: Int?
    public let genres: [TMDBGenre]
    public let voteAverage: Double?
    public let originalLanguage: String?   // ISO 639-1
    public let imdbID: String?

    enum CodingKeys: String, CodingKey {
        case id, title, overview, runtime, genres
        case releaseDate = "release_date"
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case voteAverage = "vote_average"
        case originalLanguage = "original_language"
        case imdbID = "imdb_id"
    }

    public init(id: Int, title: String, releaseDate: String?, overview: String?,
                posterPath: String?, backdropPath: String?, runtime: Int?,
                genres: [TMDBGenre], voteAverage: Double?,
                originalLanguage: String? = nil, imdbID: String? = nil) {
        self.id = id; self.title = title; self.releaseDate = releaseDate
        self.overview = overview; self.posterPath = posterPath; self.backdropPath = backdropPath
        self.runtime = runtime; self.genres = genres; self.voteAverage = voteAverage
        self.originalLanguage = originalLanguage; self.imdbID = imdbID
    }
}
```

In `TMDBModels.swift`, replace `TMDBTVDetails` with (adds two fields; `imdbID` decoded from nested `external_ids` via a custom `init(from:)`, keeping the memberwise init for tests):

```swift
public struct TMDBTVDetails: Decodable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let name: String
    public let firstAirDate: String?
    public let overview: String?
    public let posterPath: String?
    public let backdropPath: String?
    public let numberOfSeasons: Int?
    public let genres: [TMDBGenre]
    public let voteAverage: Double?
    public let originalLanguage: String?   // ISO 639-1
    public let imdbID: String?             // from append_to_response=external_ids

    enum CodingKeys: String, CodingKey {
        case id, name, overview, genres
        case firstAirDate = "first_air_date"
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case numberOfSeasons = "number_of_seasons"
        case voteAverage = "vote_average"
        case originalLanguage = "original_language"
        case externalIDs = "external_ids"
    }

    private struct ExternalIDs: Decodable { let imdb_id: String? }

    public init(id: Int, name: String, firstAirDate: String?, overview: String?,
                posterPath: String?, backdropPath: String?, numberOfSeasons: Int?,
                genres: [TMDBGenre], voteAverage: Double?,
                originalLanguage: String? = nil, imdbID: String? = nil) {
        self.id = id; self.name = name; self.firstAirDate = firstAirDate
        self.overview = overview; self.posterPath = posterPath; self.backdropPath = backdropPath
        self.numberOfSeasons = numberOfSeasons; self.genres = genres; self.voteAverage = voteAverage
        self.originalLanguage = originalLanguage; self.imdbID = imdbID
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        firstAirDate = try c.decodeIfPresent(String.self, forKey: .firstAirDate)
        overview = try c.decodeIfPresent(String.self, forKey: .overview)
        posterPath = try c.decodeIfPresent(String.self, forKey: .posterPath)
        backdropPath = try c.decodeIfPresent(String.self, forKey: .backdropPath)
        numberOfSeasons = try c.decodeIfPresent(Int.self, forKey: .numberOfSeasons)
        genres = try c.decodeIfPresent([TMDBGenre].self, forKey: .genres) ?? []
        voteAverage = try c.decodeIfPresent(Double.self, forKey: .voteAverage)
        originalLanguage = try c.decodeIfPresent(String.self, forKey: .originalLanguage)
        imdbID = try c.decodeIfPresent(ExternalIDs.self, forKey: .externalIDs)?.imdb_id
    }
}
```

In `TMDBClient.swift`, change `tvDetails` to request external_ids:

```swift
    public func tvDetails(id: Int) async throws -> TMDBTVDetails {
        try await get("tv/\(id)", [URLQueryItem(name: "append_to_response", value: "external_ids")])
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path Packages/DebridCore --filter TMDBDetailsLanguageTests`
Expected: PASS (3 tests). Also run the existing TMDB suite to confirm no regression:
`swift test --package-path Packages/DebridCore --filter TMDB`

- [ ] **Step 5: Commit**

```bash
git add Packages/DebridCore/Sources/DebridCore/Metadata/TMDBModels.swift \
        Packages/DebridCore/Sources/DebridCore/Metadata/TMDBClient.swift \
        Packages/DebridCore/Tests/DebridCoreTests/TMDBDetailsLanguageTests.swift
git commit -m "feat(core): decode TMDB originalLanguage + imdbID (movie direct, tv via external_ids)"
```

---

## Task A6: `LanguageDetector` — flag emoji / words → ISO 639-1

Pure. Maps regional-indicator flag emoji (decoded to a country code, then to a primary language) and common English language words to ISO 639-1 codes. Used to match a stream's audio languages against TMDB `original_language`.

**Files:**
- Create: `Packages/DebridCore/Sources/DebridCore/Search/LanguageDetector.swift`
- Test: `Packages/DebridCore/Tests/DebridCoreTests/LanguageDetectorTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import DebridCore

@Suite struct LanguageDetectorTests {
    let detector = LanguageDetector()

    @Test func detectsFlagEmoji() {
        #expect(detector.detect(in: "🇺🇸/🇫🇷") == ["en", "fr"])
    }

    @Test func mapsGBToEnglishAndJPToJapanese() {
        #expect(detector.detect(in: "audio 🇬🇧 🇯🇵") == ["en", "ja"])
    }

    @Test func detectsLanguageWords() {
        #expect(detector.detect(in: "Multi: English, French, Hindi") == ["en", "fr", "hi"])
    }

    @Test func dedupesAndPreservesFirstSeenOrder() {
        #expect(detector.detect(in: "🇫🇷 French 🇫🇷") == ["fr"])
    }

    @Test func ignoresUnknownTokens() {
        #expect(detector.detect(in: "no languages here 1080p x265").isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/DebridCore --filter LanguageDetectorTests`
Expected: FAIL — no `LanguageDetector`.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// Extracts audio-language ISO 639-1 codes from a stream title.
/// Recognizes regional-indicator flag emoji (mapped country→primary language) and
/// common English language words. Order = first-seen; duplicates removed.
public struct LanguageDetector: Sendable {
    public init() {}

    public func detect(in text: String) -> [String] {
        var result: [String] = []
        func add(_ code: String) { if !result.contains(code) { result.append(code) } }

        // 1) Flag emoji: consecutive regional indicator pairs → country code → language.
        let scalars = Array(text.unicodeScalars)
        var i = 0
        while i < scalars.count {
            if let c0 = Self.regionalLetter(scalars[i]), i + 1 < scalars.count,
               let c1 = Self.regionalLetter(scalars[i + 1]) {
                let country = String([c0, c1])
                if let lang = Self.countryToLanguage[country] { add(lang) }
                i += 2
            } else {
                i += 1
            }
        }

        // 2) Whole-word language names.
        let lowered = text.lowercased()
        for (word, code) in Self.wordToLanguage {
            if Self.containsWord(word, in: lowered) { add(code) }
        }
        return result
    }

    private static func regionalLetter(_ s: Unicode.Scalar) -> Character? {
        guard s.value >= 0x1F1E6 && s.value <= 0x1F1FF else { return nil }
        return Character(Unicode.Scalar(s.value - 0x1F1E6 + 0x41)!) // 'A'...'Z'
    }

    private static func containsWord(_ word: String, in lowered: String) -> Bool {
        guard let range = lowered.range(of: word) else { return false }
        let before = range.lowerBound == lowered.startIndex ? nil : lowered[lowered.index(before: range.lowerBound)]
        let after = range.upperBound == lowered.endIndex ? nil : lowered[range.upperBound]
        func isBoundary(_ ch: Character?) -> Bool { guard let ch else { return true }; return !ch.isLetter }
        return isBoundary(before) && isBoundary(after)
    }

    /// Country (ISO 3166-1 alpha-2) → primary language (ISO 639-1).
    static let countryToLanguage: [String: String] = [
        "US": "en", "GB": "en", "AU": "en", "CA": "en", "IE": "en", "NZ": "en",
        "FR": "fr", "DE": "de", "AT": "de", "ES": "es", "MX": "es", "AR": "es",
        "IT": "it", "JP": "ja", "KR": "ko", "CN": "zh", "TW": "zh", "HK": "zh",
        "RU": "ru", "PT": "pt", "BR": "pt", "NL": "nl", "SE": "sv", "NO": "no",
        "DK": "da", "FI": "fi", "PL": "pl", "TR": "tr", "IL": "he", "IN": "hi",
        "SA": "ar", "EG": "ar", "GR": "el", "CZ": "cs", "HU": "hu", "TH": "th",
        "VN": "vi", "ID": "id", "UA": "uk", "RO": "ro",
    ]

    /// English language word → ISO 639-1.
    static let wordToLanguage: [String: String] = [
        "english": "en", "french": "fr", "german": "de", "spanish": "es",
        "italian": "it", "japanese": "ja", "korean": "ko", "chinese": "zh",
        "mandarin": "zh", "cantonese": "zh", "russian": "ru", "portuguese": "pt",
        "dutch": "nl", "swedish": "sv", "norwegian": "no", "danish": "da",
        "finnish": "fi", "polish": "pl", "turkish": "tr", "hebrew": "he",
        "hindi": "hi", "arabic": "ar", "greek": "el", "czech": "cs",
        "hungarian": "hu", "thai": "th", "vietnamese": "vi", "ukrainian": "uk",
    ]
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path Packages/DebridCore --filter LanguageDetectorTests`
Expected: PASS (5 tests).

> Note: the `dedupesAndPreservesFirstSeenOrder` test relies on flags being scanned before words; since `wordToLanguage` is a dictionary (unordered), a single language there is fine, but if a test ever needs deterministic multi-word order, sort matches by their index in `lowered`. Not needed for these tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/DebridCore/Sources/DebridCore/Search/LanguageDetector.swift \
        Packages/DebridCore/Tests/DebridCoreTests/LanguageDetectorTests.swift
git commit -m "feat(core): add LanguageDetector (flag emoji + words -> ISO 639-1)"
```

---

## Task A7: Shared `qualityRank(for: ParsedRelease)` (refactor)

Extract the resolution/source/codec tier formula (currently private to `MediaSource`) into a shared free function so both `MediaSource` and the new `CachedStream` rank identically. Existing `MediaSource` ranking behavior must stay byte-identical (existing tests stay green).

**Files:**
- Create: `Packages/DebridCore/Sources/DebridCore/Library/QualityRank.swift`
- Modify: `Packages/DebridCore/Sources/DebridCore/Library/MediaSourceRanking.swift`
- Test: `Packages/DebridCore/Tests/DebridCoreTests/QualityRankTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import DebridCore

@Suite struct QualityRankTests {
    @Test func resolutionDominatesSourceAndCodec() {
        let p2160 = ParsedRelease(title: "A", resolution: "2160p", source: "HDTV", videoCodec: "h264")
        let p1080 = ParsedRelease(title: "A", resolution: "1080p", source: "REMUX", videoCodec: "HEVC")
        #expect(qualityRank(for: p2160) > qualityRank(for: p1080))
    }

    @Test func sourceBreaksResolutionTies() {
        let remux = ParsedRelease(title: "A", resolution: "1080p", source: "REMUX")
        let webdl = ParsedRelease(title: "A", resolution: "1080p", source: "WEB-DL")
        #expect(qualityRank(for: remux) > qualityRank(for: webdl))
    }

    @Test func codecBreaksSourceTies() {
        let hevc = ParsedRelease(title: "A", resolution: "1080p", source: "BluRay", videoCodec: "HEVC")
        let avc = ParsedRelease(title: "A", resolution: "1080p", source: "BluRay", videoCodec: "x264")
        #expect(qualityRank(for: hevc) > qualityRank(for: avc))
    }

    @Test func unknownFieldsRankZeroTiers() {
        #expect(qualityRank(for: ParsedRelease(title: "A")) == 0)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/DebridCore --filter QualityRankTests`
Expected: FAIL — no global `qualityRank`.

- [ ] **Step 3: Write minimal implementation**

Create `QualityRank.swift`:

```swift
/// Quality score for a parsed release. Higher is better: resolution dominates,
/// then source tier, then video codec. Shared by `MediaSource` (library) and
/// `CachedStream` (search) so both rank identically.
public func qualityRank(for parsed: ParsedRelease) -> Int {
    resolutionTier(parsed.resolution) * 10_000
        + sourceTier(parsed.source) * 100
        + codecTier(parsed.videoCodec)
}

func resolutionTier(_ r: String?) -> Int {
    switch r {                 // ParsedRelease stores resolution lowercased
    case "2160p": return 4
    case "1080p": return 3
    case "720p": return 2
    case "480p": return 1
    default: return 0
    }
}

func sourceTier(_ s: String?) -> Int {
    switch s {                 // FilenameParser.normalizeSource canonical forms
    case "REMUX": return 7
    case "BluRay": return 6
    case "WEB-DL": return 5
    case "WEBRip": return 4
    case "BDRip": return 3
    case "HDTV": return 2
    case "HDRip", "DVDRip": return 1
    default: return 0
    }
}

func codecTier(_ c: String?) -> Int {
    switch c {                 // H.265 aliases rank above H.264 aliases
    case "HEVC", "x265", "h265": return 2
    case "AVC", "x264", "h264": return 1
    default: return 0
    }
}
```

Replace the body of `MediaSourceRanking.swift`'s `qualityRank` and delete its private tier helpers:

```swift
/// Quality ranking for picking the default ("best") source and ordering the Versions list.
public extension MediaSource {
    /// Higher is better. Resolution dominates, then source tier, then video codec.
    var qualityRank: Int { DebridCore.qualityRank(for: parsed) }
}

public extension Array where Element == MediaSource {
    /// Sources best-first. Deterministic: ties break by torrentID, then fileID.
    func bestFirst() -> [MediaSource] {
        sorted { a, b in
            if a.qualityRank != b.qualityRank { return a.qualityRank > b.qualityRank }
            if a.torrentID != b.torrentID { return a.torrentID < b.torrentID }
            return (a.fileID ?? -1) < (b.fileID ?? -1)
        }
    }

    /// The single best source, or nil when empty.
    var best: MediaSource? { bestFirst().first }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path Packages/DebridCore --filter QualityRankTests`
Then confirm no regression in the existing source-ranking suite:
`swift test --package-path Packages/DebridCore --filter Ranking`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/DebridCore/Sources/DebridCore/Library/QualityRank.swift \
        Packages/DebridCore/Sources/DebridCore/Library/MediaSourceRanking.swift \
        Packages/DebridCore/Tests/DebridCoreTests/QualityRankTests.swift
git commit -m "refactor(core): extract shared qualityRank(for:) from MediaSource"
```

---

## Task A8: `StreamSource` seam + models

`StreamQuery`, `StreamKind`, `CachedStream`, and the `StreamSource` protocol. Pure data + protocol; no networking yet.

**Files:**
- Create: `Packages/DebridCore/Sources/DebridCore/Search/StreamModels.swift`
- Create: `Packages/DebridCore/Sources/DebridCore/Search/StreamSource.swift`
- Test: covered by Task A9 (ranking) and A10 (Comet). Add a tiny model test here.
- Test: `Packages/DebridCore/Tests/DebridCoreTests/CachedStreamRankingTests.swift` (created in A9; this task adds no separate test file — the models are exercised by A9/A10). To satisfy "test first", add one model test inline below.

- [ ] **Step 1: Write the failing test**

Create `Packages/DebridCore/Tests/DebridCoreTests/StreamModelsTests.swift`:

```swift
import Testing
@testable import DebridCore

@Suite struct StreamModelsTests {
    @Test func cachedStreamQualityRankUsesParsed() {
        let s = CachedStream(infoHash: "abc", fileIdx: 1, rawTitle: "Movie 2160p REMUX",
                             parsed: ParsedRelease(title: "Movie", resolution: "2160p", source: "REMUX"),
                             languages: ["en"], sizeBytes: 100, sourceName: "RD")
        #expect(s.qualityRank == qualityRank(for: s.parsed))
        #expect(s.qualityRank > 0)
    }

    @Test func streamKindSeriesCarriesSeasonEpisode() {
        let q = StreamQuery(imdbID: "tt1", kind: .series(season: 2, episode: 5), originalLanguage: "en")
        if case let .series(season, episode) = q.kind {
            #expect(season == 2); #expect(episode == 5)
        } else { Issue.record("expected series") }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/DebridCore --filter StreamModelsTests`
Expected: FAIL — no `CachedStream`/`StreamQuery`/`StreamKind`.

- [ ] **Step 3: Write minimal implementation**

Create `StreamModels.swift`:

```swift
import Foundation

/// What to search for on a `StreamSource`.
public struct StreamQuery: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case movie
        case series(season: Int, episode: Int)
    }
    public let imdbID: String          // e.g. "tt0133093"
    public let kind: Kind
    public let originalLanguage: String? // ISO 639-1, from TMDB; drives ranking

    public init(imdbID: String, kind: Kind, originalLanguage: String?) {
        self.imdbID = imdbID; self.kind = kind; self.originalLanguage = originalLanguage
    }
}

/// Convenience alias so call sites can write `StreamKind` if preferred.
public typealias StreamKind = StreamQuery.Kind

/// One already-cached torrent returned by a `StreamSource`, ready to add to RD.
public struct CachedStream: Sendable, Equatable, Identifiable {
    public let infoHash: String        // 40-hex; what we addMagnet
    public let fileIdx: Int?           // addon's chosen file index hint (may be nil)
    public let rawTitle: String        // the torrent's release name (for parsing/display)
    public let parsed: ParsedRelease   // quality fields from rawTitle
    public let languages: [String]     // detected audio languages (ISO 639-1)
    public let sizeBytes: Int?
    public let sourceName: String?     // e.g. "RD" / addon label

    public var id: String { infoHash }

    /// Higher is better — same formula as the library's `MediaSource`.
    public var qualityRank: Int { DebridCore.qualityRank(for: parsed) }

    public init(infoHash: String, fileIdx: Int?, rawTitle: String, parsed: ParsedRelease,
                languages: [String], sizeBytes: Int?, sourceName: String?) {
        self.infoHash = infoHash; self.fileIdx = fileIdx; self.rawTitle = rawTitle
        self.parsed = parsed; self.languages = languages; self.sizeBytes = sizeBytes
        self.sourceName = sourceName
    }
}
```

Create `StreamSource.swift`:

```swift
/// A source of already-cached torrents for a title (e.g. the Comet Stremio addon).
public protocol StreamSource: Sendable {
    /// Returns instantly-cached streams for the query, unranked (caller ranks).
    func streams(for query: StreamQuery) async throws -> [CachedStream]
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path Packages/DebridCore --filter StreamModelsTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Packages/DebridCore/Sources/DebridCore/Search/StreamModels.swift \
        Packages/DebridCore/Sources/DebridCore/Search/StreamSource.swift \
        Packages/DebridCore/Tests/DebridCoreTests/StreamModelsTests.swift
git commit -m "feat(core): add StreamSource seam + StreamQuery/CachedStream models"
```

---

## Task A9: `CachedStream` ranking — `rankedFor` / `bestMatch`

Rank cached streams: original-language audio first, then quality, then size. `bestMatch` returns the top pick plus an `isFallback` flag (true when the pick lacks the original language).

**Files:**
- Create: `Packages/DebridCore/Sources/DebridCore/Search/CachedStreamRanking.swift`
- Test: `Packages/DebridCore/Tests/DebridCoreTests/CachedStreamRankingTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import DebridCore

@Suite struct CachedStreamRankingTests {
    func stream(_ hash: String, res: String, langs: [String], size: Int) -> CachedStream {
        CachedStream(infoHash: hash, fileIdx: nil, rawTitle: "t",
                     parsed: ParsedRelease(title: "t", resolution: res),
                     languages: langs, sizeBytes: size, sourceName: nil)
    }

    @Test func originalLanguageOutranksHigherQuality() {
        let dub4k = stream("a", res: "2160p", langs: ["en"], size: 100)
        let orig1080 = stream("b", res: "1080p", langs: ["fr"], size: 50)
        let ranked = [dub4k, orig1080].rankedFor(originalLanguage: "fr")
        #expect(ranked.first?.infoHash == "b")
    }

    @Test func qualityBreaksTiesAmongOriginalLanguage() {
        let orig4k = stream("a", res: "2160p", langs: ["fr"], size: 10)
        let orig1080 = stream("b", res: "1080p", langs: ["fr"], size: 10)
        let ranked = [orig1080, orig4k].rankedFor(originalLanguage: "fr")
        #expect(ranked.first?.infoHash == "a")
    }

    @Test func sizeBreaksQualityTies() {
        let big = stream("a", res: "2160p", langs: ["fr"], size: 200)
        let small = stream("b", res: "2160p", langs: ["fr"], size: 100)
        let ranked = [small, big].rankedFor(originalLanguage: "fr")
        #expect(ranked.first?.infoHash == "a")
    }

    @Test func bestMatchFlagsFallbackWhenNoOriginalLanguage() {
        let dub = stream("a", res: "2160p", langs: ["en"], size: 100)
        let match = [dub].bestMatch(originalLanguage: "fr")
        #expect(match?.stream.infoHash == "a")
        #expect(match?.isFallback == true)
    }

    @Test func bestMatchNotFallbackWhenOriginalPresent() {
        let orig = stream("a", res: "1080p", langs: ["fr"], size: 100)
        let match = [orig].bestMatch(originalLanguage: "fr")
        #expect(match?.isFallback == false)
    }

    @Test func nilOriginalLanguageRanksByQualityOnly() {
        let hi = stream("a", res: "2160p", langs: ["en"], size: 1)
        let lo = stream("b", res: "720p", langs: ["fr"], size: 1)
        let ranked = [lo, hi].rankedFor(originalLanguage: nil)
        #expect(ranked.first?.infoHash == "a")
        #expect([hi].bestMatch(originalLanguage: nil)?.isFallback == false)
    }

    @Test func bestMatchNilWhenEmpty() {
        #expect([CachedStream]().bestMatch(originalLanguage: "en") == nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/DebridCore --filter CachedStreamRankingTests`
Expected: FAIL — no `rankedFor`/`bestMatch`.

- [ ] **Step 3: Write minimal implementation**

```swift
/// Ranking for cached search results: original-language audio first, then quality, then size.
public extension CachedStream {
    /// Whether this stream's audio includes `language` (nil language → false).
    func includes(language: String?) -> Bool {
        guard let language else { return false }
        return languages.contains(language)
    }
}

public extension Array where Element == CachedStream {
    /// Best-first. Original-language audio dominates, then quality, then size, then infoHash
    /// (deterministic tiebreak). When `originalLanguage` is nil, ranks by quality/size only.
    func rankedFor(originalLanguage: String?) -> [CachedStream] {
        sorted { a, b in
            let ao = a.includes(language: originalLanguage)
            let bo = b.includes(language: originalLanguage)
            if ao != bo { return ao && !bo }
            if a.qualityRank != b.qualityRank { return a.qualityRank > b.qualityRank }
            let asz = a.sizeBytes ?? 0, bsz = b.sizeBytes ?? 0
            if asz != bsz { return asz > bsz }
            return a.infoHash < b.infoHash
        }
    }

    /// The top pick plus whether it's a language fallback (lacks the original language).
    /// `isFallback` is false when `originalLanguage` is nil (no preference to miss).
    func bestMatch(originalLanguage: String?) -> (stream: CachedStream, isFallback: Bool)? {
        guard let best = rankedFor(originalLanguage: originalLanguage).first else { return nil }
        let isFallback = (originalLanguage != nil) && !best.includes(language: originalLanguage)
        return (best, isFallback)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path Packages/DebridCore --filter CachedStreamRankingTests`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add Packages/DebridCore/Sources/DebridCore/Search/CachedStreamRanking.swift \
        Packages/DebridCore/Tests/DebridCoreTests/CachedStreamRankingTests.swift
git commit -m "feat(core): rank cached streams by original-language then quality (+fallback flag)"
```

---

## Task A10: `CometStreamSource` + live-fixture verification

The first `StreamSource`: builds the base64 config + Stremio stream URL, fetches, decodes, and maps each stream to a `CachedStream` (infohash + file index parsed from the `/playback/` URL path; quality via `FilenameParser`; languages via `LanguageDetector`).

**Files:**
- Create: `Packages/DebridCore/Sources/DebridCore/Search/CometStreamSource.swift`
- Create: `Packages/DebridCore/Tests/DebridCoreTests/Fixtures/comet-movie-cached.json`
- Test: `Packages/DebridCore/Tests/DebridCoreTests/CometStreamSourceTests.swift`

### Step 0 (do this FIRST — verify the live wire format)

The exact serialized shape of a **cached RD stream** could not be confirmed from a live keyed call during planning (only from source-reading). Before trusting the decoder, capture one real response with the owner's RD token and sanity-check the fixture against it. Run (token NEVER committed/logged — paste it into the shell only):

```bash
# Replace <RD_TOKEN>. tt0111161 = The Shawshank Redemption.
CFG=$(printf '{"debridService":"realdebrid","debridApiKey":"<RD_TOKEN>","cachedOnly":true,"resultFormat":["all"]}' | base64 | tr -d '\n')
curl -s "https://comet.elfhosted.com/${CFG}/stream/movie/tt0111161.json" | python3 -m json.tool | head -60
```

Confirm: each stream has a `url` containing `/playback/<40-hex>/`, a `name` with `⚡`, a multi-line `description`, and `behaviorHints.videoSize`. If the field names differ from the fixture below, update `CometStreamDTO`'s `CodingKeys` and the fixture to match before finishing the task. **Do not paste the real response (it may embed the token in URLs) into the repo — hand-write the sanitized fixture below.**

- [ ] **Step 1: Write the fixture + failing test**

Create `Fixtures/comet-movie-cached.json` (sanitized, representative — hashes are dummy 40-hex):

```json
{
  "streams": [
    {
      "name": "[RD⚡] Comet 2160p",
      "description": "📄 The.Matrix.1999.2160p.UHD.BluRay.REMUX.HEVC.TrueHD-GROUP\n📹 HEVC | 🔊 TrueHD\n⭐ REMUX | 🏷️ GROUP\n👤 50 💾 60.1 GB 🔎 Tracker\n🇺🇸/🇫🇷",
      "behaviorHints": { "bingeGroup": "comet|aaaa", "filename": "The.Matrix.mkv", "videoSize": 64500000000 },
      "url": "https://comet.elfhosted.com/playback/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/0/0/n/n?name=x"
    },
    {
      "name": "[RD⚡] Comet 1080p",
      "description": "📄 The.Matrix.1999.1080p.BluRay.x264-GROUP\n📹 x264 | 🔊 DTS\n⭐ BluRay | 🏷️ GROUP\n👤 30 💾 12.0 GB 🔎 Tracker\n🇺🇸",
      "behaviorHints": { "bingeGroup": "comet|bbbb", "filename": "The.Matrix.1080p.mkv", "videoSize": 12000000000 },
      "url": "https://comet.elfhosted.com/playback/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/0/n/n/n?name=y"
    },
    {
      "name": "[⛔️] Comet",
      "description": "This stream has no playback url and must be ignored",
      "url": "https://comet.elfhosted.com/configure"
    }
  ]
}
```

Create `CometStreamSourceTests.swift`:

```swift
import Testing
import Foundation
@testable import DebridCore

extension MockTests {
    @Suite struct CometStreamSourceTests {
        init() { MockURLProtocol.handler = nil }

        struct StubTokens: AccessTokenProviding {
            func validAccessToken() async throws -> String { "RDTOKEN" }
        }

        func fixture(_ name: String) throws -> String {
            let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!
            return try String(contentsOf: url, encoding: .utf8)
        }

        @Test func buildsCorrectMovieURLWithBase64Config() async throws {
            MockURLProtocol.handler = { request in
                let url = request.url!.absoluteString
                #expect(url.contains("/stream/movie/tt0133093.json"))
                // config segment is base64 of the JSON containing the token
                let path = request.url!.path
                let segment = path.split(separator: "/").first.map(String.init) ?? ""
                let decoded = Data(base64Encoded: segment).map { String(decoding: $0, as: UTF8.self) } ?? ""
                #expect(decoded.contains("\"debridApiKey\":\"RDTOKEN\""))
                #expect(decoded.contains("\"cachedOnly\":true"))
                let r = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (r, Data(#"{"streams":[]}"#.utf8))
            }
            let source = CometStreamSource(http: HTTPClient(session: .mock), tokens: StubTokens())
            _ = try await source.streams(for: StreamQuery(imdbID: "tt0133093", kind: .movie, originalLanguage: "en"))
        }

        @Test func buildsSeriesIDWithSeasonEpisode() async throws {
            MockURLProtocol.handler = { request in
                #expect(request.url!.absoluteString.contains("/stream/series/tt0944947:1:2.json"))
                let r = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (r, Data(#"{"streams":[]}"#.utf8))
            }
            let source = CometStreamSource(http: HTTPClient(session: .mock), tokens: StubTokens())
            _ = try await source.streams(for: StreamQuery(imdbID: "tt0944947",
                                                          kind: .series(season: 1, episode: 2),
                                                          originalLanguage: "en"))
        }

        @Test func mapsCachedStreamsAndSkipsNonPlayback() async throws {
            let json = try fixture("comet-movie-cached")
            MockURLProtocol.stub(status: 200, json: json)
            let source = CometStreamSource(http: HTTPClient(session: .mock), tokens: StubTokens())
            let streams = try await source.streams(for: StreamQuery(imdbID: "tt0133093", kind: .movie, originalLanguage: "fr"))

            #expect(streams.count == 2)  // ⛔️ no-playback stream skipped
            let first = streams[0]
            #expect(first.infoHash == "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
            #expect(first.parsed.resolution == "2160p")
            #expect(first.parsed.source == "REMUX")
            #expect(first.languages == ["en", "fr"])
            #expect(first.sizeBytes == 64500000000)
            #expect(streams[1].infoHash == "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
            #expect(streams[1].languages == ["en"])
        }

        @Test func parsesFileIndexFromPlaybackURLWhenNumeric() async throws {
            // url segment order: /playback/{hash}/{entry}/{fileIdx}/{s}/{e}
            let json = #"""
            {"streams":[{"name":"[RD⚡] Comet 1080p",
              "description":"📄 Show.S01E02.1080p.WEB-DL.x264-G\n🇺🇸",
              "behaviorHints":{"videoSize":900},
              "url":"https://comet.elfhosted.com/playback/cccccccccccccccccccccccccccccccccccccccc/0/3/1/2?x=1"}]}
            """#
            MockURLProtocol.stub(status: 200, json: json)
            let source = CometStreamSource(http: HTTPClient(session: .mock), tokens: StubTokens())
            let streams = try await source.streams(for: StreamQuery(imdbID: "tt1", kind: .series(season: 1, episode: 2), originalLanguage: "en"))
            #expect(streams.first?.fileIdx == 3)
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/DebridCore --filter CometStreamSourceTests`
Expected: FAIL — no `CometStreamSource` (and possibly a fixture-bundling error until Step 3 adds resources to `Package.swift`).

- [ ] **Step 3: Write minimal implementation**

First ensure test fixtures are bundled. In `Packages/DebridCore/Package.swift`, the test target needs the Fixtures resource. Add to the `.testTarget(name: "DebridCoreTests", …)` declaration:

```swift
            resources: [.copy("Fixtures")]
```

(If a `resources:` array already exists on the test target, append `.copy("Fixtures")` to it instead of adding a second parameter.)

Create `CometStreamSource.swift`:

```swift
import Foundation

/// `StreamSource` backed by the Comet Stremio addon. Returns instantly-cached torrents
/// (config sets `cachedOnly:true`) for a title, with quality + languages parsed from each
/// stream's title text and the infohash/file-index parsed from its `/playback/` URL.
public struct CometStreamSource: StreamSource {
    public static let defaultBaseURL = URL(string: "https://comet.elfhosted.com")!

    private let baseURL: URL
    private let http: HTTPClient
    private let tokens: any AccessTokenProviding
    private let parser: FilenameParser
    private let languages: LanguageDetector

    public init(baseURL: URL = CometStreamSource.defaultBaseURL,
                http: HTTPClient = HTTPClient(),
                tokens: any AccessTokenProviding,
                parser: FilenameParser = FilenameParser(),
                languages: LanguageDetector = LanguageDetector()) {
        self.baseURL = baseURL; self.http = http; self.tokens = tokens
        self.parser = parser; self.languages = languages
    }

    public func streams(for query: StreamQuery) async throws -> [CachedStream] {
        let token = try await tokens.validAccessToken()
        let config = #"{"debridService":"realdebrid","debridApiKey":""# + token
            + #"","cachedOnly":true,"resultFormat":["all"]}"#
        let b64 = Data(config.utf8).base64EncodedString()

        let id: String
        let type: String
        switch query.kind {
        case .movie:
            type = "movie"; id = query.imdbID
        case let .series(season, episode):
            type = "series"; id = "\(query.imdbID):\(season):\(episode)"
        }

        let url = baseURL.appending(path: "\(b64)/stream/\(type)/\(id).json")
        let response: CometStreamResponse = try await http.get(url)
        return response.streams.compactMap { map($0) }
    }

    private func map(_ dto: CometStreamDTO) -> CachedStream? {
        guard let (hash, fileIdx) = Self.parsePlayback(dto.url) else { return nil }
        let text = dto.description ?? dto.name ?? ""
        let rawTitle = Self.torrentTitle(from: text) ?? dto.name ?? hash
        return CachedStream(
            infoHash: hash,
            fileIdx: fileIdx,
            rawTitle: rawTitle,
            parsed: parser.parse(rawTitle),
            languages: languages.detect(in: text),
            sizeBytes: dto.behaviorHints?.videoSize,
            sourceName: dto.name)
    }

    /// Extracts (infohash, fileIdx?) from `…/playback/{hash}/{entry}/{fileIdx}/{s}/{e}`.
    /// Returns nil when the url has no `/playback/<40-hex>/` segment.
    static func parsePlayback(_ urlString: String?) -> (hash: String, fileIdx: Int?)? {
        guard let urlString, let range = urlString.range(of: "/playback/") else { return nil }
        let tail = urlString[range.upperBound...]
        let segments = tail.split(separator: "/", omittingEmptySubsequences: false)
        guard let first = segments.first else { return nil }
        let hash = String(first)
        guard hash.count == 40, hash.allSatisfy({ $0.isHexDigit }) else { return nil }
        // segments: [hash, entry, fileIdx, season, episode...] — fileIdx is index 2
        var fileIdx: Int? = nil
        if segments.count > 2 {
            // strip any query string on the last used segment
            let raw = segments[2].split(separator: "?").first.map(String.init) ?? String(segments[2])
            fileIdx = Int(raw)  // "n" → nil
        }
        return (hash, fileIdx)
    }

    /// First description line, stripped of the leading "📄 " marker.
    static func torrentTitle(from description: String) -> String? {
        guard let firstLine = description.split(separator: "\n").first else { return nil }
        let trimmed = firstLine.drop(while: { $0 == "📄" || $0 == " " })
        return trimmed.isEmpty ? nil : String(trimmed)
    }
}

// MARK: - Wire DTOs (Comet/Stremio stream response)

struct CometStreamResponse: Decodable { let streams: [CometStreamDTO] }

struct CometStreamDTO: Decodable {
    let name: String?
    let description: String?
    let url: String?
    let behaviorHints: BehaviorHints?

    struct BehaviorHints: Decodable {
        let videoSize: Int?
        let filename: String?
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path Packages/DebridCore --filter CometStreamSourceTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Packages/DebridCore/Sources/DebridCore/Search/CometStreamSource.swift \
        Packages/DebridCore/Tests/DebridCoreTests/CometStreamSourceTests.swift \
        Packages/DebridCore/Tests/DebridCoreTests/Fixtures/comet-movie-cached.json \
        Packages/DebridCore/Package.swift
git commit -m "feat(core): add CometStreamSource (cached-only Stremio addon StreamSource)"
```

---

## Slice A done — full verification

- [ ] Run the WHOLE brain suite (not `--filter`): `swift test --package-path Packages/DebridCore`
  Expected: all green — every pre-existing DebridCore test (the base-branch baseline) plus the new ones added here.
- [ ] Zero-warning bar: `swift build --package-path Packages/DebridCore 2>&1 | grep -i warning`
  Expected: prints nothing.
- [ ] Confirm Step 0 of A10 was actually run against a live keyed call and the fixture matches reality.

## Self-review notes (carried into review)

- `add(magnetHash:)` selects **all** files (robust instant path; season packs surface every episode; movies pick the largest video at play time via the existing `primaryVideoFile()`). Precise per-episode selection using `CachedStream.fileIdx` is a future refinement — `fileIdx` is captured but unused by `add()`.
- `CometStreamSource` holds an `AccessTokenProviding` and rebuilds the config per call so the embedded RD token is always fresh.
- The RD token is embedded in the addon URL by design (the addon needs it to check the user's cache). Per the existing logging rule, **do not add request-URL logging to `CometStreamSource` or the RD write calls** — the token rides in the path/body.
- Language match is exact ISO 639-1 (`languages.contains(originalLanguage)`); for English-original titles the fallback path rarely triggers since most releases are English.

## Next slices (separate plans, after A merges)

- **Slice B (DebridUI):** `SearchStore` (debounced TMDB search) + `AddStore` (fetch streams → `bestMatch` → `addBest`/`add`/`addAndPlay` + add-progress state), host-free tests.
- **Slice C (apps):** Search tab + results grid + Add screen (Get best · Add & Play · More versions) on SeretTV + SeretMobile, wired through `AppSession`.
