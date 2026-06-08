# OMDb Ratings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show IMDb, Rotten Tomatoes, and Metacritic ratings on the movie/show detail screens of both Seret apps, sourced from OMDb by the IMDb id TMDB already provides.

**Architecture:** A new `OMDbClient` (DebridCore) fetches ratings by IMDb id, reusing the existing `HTTPClient`. A 7-day persistent `OMDbRatingsCache` keeps us under OMDb's 1,000/day free quota. A `RatingsProviding` seam (DebridUI) with an `OMDbRatingsService` conformance wires into `DetailStore` as a non-blocking supplemental fetch. Each app renders a native `RatingsRow` (the codebase shares logic, not screens).

**Tech Stack:** Swift 6, Swift Testing, SwiftUI, XcodeGen. No new third-party dependencies.

**Branch:** Build on the current `feat/cloudkit-sync` branch. **Stage only the paths listed in each task's commit step** — never `git add -A` (the owner has parallel uncommitted work in `Info.plist`, `project.yml`, `CLAUDE.md`, and entitlements files).

**Spec:** `docs/superpowers/specs/2026-06-08-omdb-ratings-design.md`

---

## File Structure

**Create (DebridCore — the brain):**
- `Packages/DebridCore/Sources/DebridCore/Metadata/OMDbModels.swift` — `OMDbRatings`, `OMDbResponse`, `OMDbError`
- `Packages/DebridCore/Sources/DebridCore/Metadata/OMDbClient.swift` — `OMDbClient`
- `Packages/DebridCore/Sources/DebridCore/Metadata/OMDbRatingsCache.swift` — `OMDbRatingsCache` actor

**Create (DebridUI — shared presentation):**
- `Shared/DebridUI/Sources/DebridUI/Detail/RatingsProviding.swift` — `RatingsProviding` protocol + `OMDbRatingsService`

**Create (apps — native views):**
- `Apps/SeretMobile/Detail/RatingsRow.swift`
- `Apps/SeretTV/Detail/RatingsRow.swift`

**Modify:**
- `Shared/DebridUI/Sources/DebridUI/Detail/DetailStore.swift` — add `ratings`/`ratingsState` + non-blocking fetch
- `Shared/DebridUI/Sources/DebridUI/Shell/AppSession.swift` — compose + vend `ratingsProvider`
- `Shared/DebridUI/Sources/DebridUI/Support/Secrets.swift` — `omdbAPIKey`
- `Apps/SeretMobile/Detail/MovieDetail.swift` + `ShowDetail.swift` — place `RatingsRow`
- `Apps/SeretTV/Detail/MovieDetailView.swift` + `ShowDetailView.swift` — place `RatingsRow`
- `Apps/SeretMobile/Detail/DetailScreen.swift` + `Apps/SeretTV/Detail/DetailView.swift` — thread `ratings:`
- `Apps/SeretMobile/Shell/RootView.swift` + `Apps/SeretTV/Shell/LibraryShell.swift` — pass `session.ratingsProvider`
- `Secrets.example.xcconfig`, `Secrets.xcconfig`, `project.yml` — `OMDB_API_KEY` plumbing

**Test:**
- `Packages/DebridCore/Tests/DebridCoreTests/OMDbClientTests.swift`
- `Packages/DebridCore/Tests/DebridCoreTests/OMDbRatingsCacheTests.swift`
- `Shared/DebridUI/Tests/DebridUITests/OMDbRatingsServiceTests.swift`
- `Shared/DebridUI/Tests/DebridUITests/RatingsDetailStoreTests.swift`

---

## Task 1: OMDb data model + response mapping (DebridCore)

**Files:**
- Create: `Packages/DebridCore/Sources/DebridCore/Metadata/OMDbModels.swift`
- Test: `Packages/DebridCore/Tests/DebridCoreTests/OMDbClientTests.swift` (the `hasAny` test here; decode tests added in Task 2)

- [ ] **Step 1: Write the model**

Create `Packages/DebridCore/Sources/DebridCore/Metadata/OMDbModels.swift`:

```swift
import Foundation

/// Derived ratings for a title, mapped from an OMDb response. All optional — OMDb routinely
/// omits Rotten Tomatoes / Metacritic for older or foreign titles.
public struct OMDbRatings: Sendable, Equatable, Codable {
    public let imdb: Double?           // 0.0–10.0
    public let rottenTomatoes: Int?    // 0–100 (percent)
    public let metacritic: Int?        // 0–100

    public init(imdb: Double?, rottenTomatoes: Int?, metacritic: Int?) {
        self.imdb = imdb
        self.rottenTomatoes = rottenTomatoes
        self.metacritic = metacritic
    }

    /// True when at least one score is present — gates whether the UI shows the ratings row.
    public var hasAny: Bool { imdb != nil || rottenTomatoes != nil || metacritic != nil }
}

public enum OMDbError: Error, Equatable {
    /// OMDb returned `"Response":"False"` (e.g. unknown IMDb id), carrying its `Error` text.
    case notFound(String)
}

/// The OMDb wire response (`?i=tt…`). Capitalized JSON keys mapped to Swift names.
struct OMDbResponse: Decodable {
    let response: String
    let error: String?
    let imdbRating: String?     // "8.7" or "N/A"
    let metascore: String?      // "73" or "N/A"
    let ratings: [Rating]?

    struct Rating: Decodable {
        let source: String      // "Rotten Tomatoes", "Internet Movie Database", "Metacritic"
        let value: String       // "88%", "8.7/10", "73/100"
        enum CodingKeys: String, CodingKey { case source = "Source", value = "Value" }
    }

    enum CodingKeys: String, CodingKey {
        case response = "Response", error = "Error"
        case imdbRating
        case metascore = "Metascore"
        case ratings = "Ratings"
    }
}

extension OMDbRatings {
    /// Map the OMDb wire shape to the derived ratings. IMDb from `imdbRating`, Metacritic from
    /// `Metascore`, Rotten Tomatoes parsed out of the `Ratings` array ("88%"). "N/A" → nil.
    init(from r: OMDbResponse) {
        func double(_ s: String?) -> Double? {
            guard let s, s != "N/A" else { return nil }
            return Double(s)
        }
        func int(_ s: String?) -> Int? {
            guard let s, s != "N/A" else { return nil }
            return Int(s)
        }
        func percent(_ s: String?) -> Int? {
            guard let s else { return nil }
            return Int(s.replacingOccurrences(of: "%", with: ""))
        }
        let rt = r.ratings?.first { $0.source == "Rotten Tomatoes" }?.value
        self.init(imdb: double(r.imdbRating),
                  rottenTomatoes: percent(rt),
                  metacritic: int(r.metascore))
    }
}
```

- [ ] **Step 2: Write the failing test for `hasAny`**

Create `Packages/DebridCore/Tests/DebridCoreTests/OMDbClientTests.swift`:

```swift
import Testing
import Foundation
@testable import DebridCore

struct OMDbRatingsValueTests {
    @Test func hasAnyTrueWithAnyScore() {
        #expect(OMDbRatings(imdb: 8.7, rottenTomatoes: nil, metacritic: nil).hasAny)
        #expect(OMDbRatings(imdb: nil, rottenTomatoes: 88, metacritic: nil).hasAny)
        #expect(OMDbRatings(imdb: nil, rottenTomatoes: nil, metacritic: 73).hasAny)
    }

    @Test func hasAnyFalseWhenAllNil() {
        #expect(!OMDbRatings(imdb: nil, rottenTomatoes: nil, metacritic: nil).hasAny)
    }
}
```

- [ ] **Step 3: Run the test to verify it passes**

Run: `swift test --package-path Packages/DebridCore --filter OMDbRatingsValueTests`
Expected: PASS (the model compiles and `hasAny` behaves).

- [ ] **Step 4: Verify zero warnings**

Run: `swift build --package-path Packages/DebridCore 2>&1 | grep -i warning`
Expected: no output.

- [ ] **Step 5: Commit**

```bash
git add Packages/DebridCore/Sources/DebridCore/Metadata/OMDbModels.swift \
        Packages/DebridCore/Tests/DebridCoreTests/OMDbClientTests.swift
git commit -m "feat(core): OMDb ratings model + response mapping"
```

---

## Task 2: OMDbClient (DebridCore)

**Files:**
- Create: `Packages/DebridCore/Sources/DebridCore/Metadata/OMDbClient.swift`
- Test: `Packages/DebridCore/Tests/DebridCoreTests/OMDbClientTests.swift` (append a `MockTests`-nested suite)

- [ ] **Step 1: Write the failing decode tests**

Append to `Packages/DebridCore/Tests/DebridCoreTests/OMDbClientTests.swift`:

```swift
extension MockTests {
    @Suite struct OMDbClientTests {
        init() { MockURLProtocol.handler = nil }

        func client() -> OMDbClient { OMDbClient(apiKey: "KEY", http: HTTPClient(session: .mock)) }

        @Test func parsesAllThreeRatings() async throws {
            MockURLProtocol.stub(status: 200, json: """
            {"Title":"The Matrix","imdbRating":"8.7","Metascore":"73",
             "Ratings":[{"Source":"Internet Movie Database","Value":"8.7/10"},
                        {"Source":"Rotten Tomatoes","Value":"88%"},
                        {"Source":"Metacritic","Value":"73/100"}],
             "Response":"True"}
            """)
            let r = try await client().ratings(imdbID: "tt0133093")
            #expect(r.imdb == 8.7)
            #expect(r.rottenTomatoes == 88)
            #expect(r.metacritic == 73)
        }

        @Test func sendsApiKeyAndImdbID() async throws {
            MockURLProtocol.handler = { request in
                let url = request.url!.absoluteString
                #expect(url.contains("omdbapi.com"))
                #expect(url.contains("apikey=KEY"))
                #expect(url.contains("i=tt0133093"))
                let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (resp, Data(#"{"Response":"True","imdbRating":"8.7"}"#.utf8))
            }
            _ = try await client().ratings(imdbID: "tt0133093")
        }

        @Test func missingRottenTomatoesIsNil() async throws {
            MockURLProtocol.stub(status: 200, json: """
            {"imdbRating":"7.2","Metascore":"N/A",
             "Ratings":[{"Source":"Internet Movie Database","Value":"7.2/10"}],
             "Response":"True"}
            """)
            let r = try await client().ratings(imdbID: "tt1")
            #expect(r.imdb == 7.2)
            #expect(r.rottenTomatoes == nil)
            #expect(r.metacritic == nil)
        }

        @Test func allRatingsMissing() async throws {
            MockURLProtocol.stub(status: 200, json: #"{"imdbRating":"N/A","Metascore":"N/A","Response":"True"}"#)
            let r = try await client().ratings(imdbID: "tt2")
            #expect(!r.hasAny)
        }

        @Test func responseFalseThrowsNotFound() async throws {
            MockURLProtocol.stub(status: 200, json: #"{"Response":"False","Error":"Incorrect IMDb ID."}"#)
            await #expect(throws: OMDbError.notFound("Incorrect IMDb ID.")) {
                _ = try await client().ratings(imdbID: "bad")
            }
        }

        @Test func tvSeriesResponseParses() async throws {
            MockURLProtocol.stub(status: 200, json: """
            {"Title":"Breaking Bad","Type":"series","imdbRating":"9.5","Metascore":"N/A",
             "Ratings":[{"Source":"Internet Movie Database","Value":"9.5/10"}],
             "Response":"True"}
            """)
            let r = try await client().ratings(imdbID: "tt0903747")
            #expect(r.imdb == 9.5)
        }
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path Packages/DebridCore --filter OMDbClientTests`
Expected: FAIL — `OMDbClient` is not defined.

- [ ] **Step 3: Write the client**

Create `Packages/DebridCore/Sources/DebridCore/Metadata/OMDbClient.swift`:

```swift
import Foundation

/// Looks up external ratings (IMDb / Rotten Tomatoes / Metacritic) for a title by its IMDb id
/// via OMDb (`https://www.omdbapi.com/?apikey=…&i=tt…`). The key is injected; tests mock the
/// transport. OMDb returns all three ratings in one call.
public struct OMDbClient: Sendable {
    public static let base = URL(string: "https://www.omdbapi.com/")!

    private let apiKey: String
    private let http: HTTPClient

    public init(apiKey: String, http: HTTPClient = HTTPClient()) {
        self.apiKey = apiKey
        self.http = http
    }

    public func ratings(imdbID: String) async throws -> OMDbRatings {
        var comps = URLComponents(url: Self.base, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "apikey", value: apiKey),
            URLQueryItem(name: "i", value: imdbID),
        ]
        let response: OMDbResponse = try await http.get(comps.url!)
        guard response.response == "True" else {
            throw OMDbError.notFound(response.error ?? "Not found")
        }
        return OMDbRatings(from: response)
    }
}
```

- [ ] **Step 4: Run to verify the suite passes**

Run: `swift test --package-path Packages/DebridCore --filter OMDbClientTests`
Expected: PASS (all 6 tests).

- [ ] **Step 5: Verify zero warnings**

Run: `swift build --package-path Packages/DebridCore 2>&1 | grep -i warning`
Expected: no output.

- [ ] **Step 6: Commit**

```bash
git add Packages/DebridCore/Sources/DebridCore/Metadata/OMDbClient.swift \
        Packages/DebridCore/Tests/DebridCoreTests/OMDbClientTests.swift
git commit -m "feat(core): OMDbClient — fetch ratings by IMDb id"
```

---

## Task 3: OMDbRatingsCache (DebridCore)

**Files:**
- Create: `Packages/DebridCore/Sources/DebridCore/Metadata/OMDbRatingsCache.swift`
- Test: `Packages/DebridCore/Tests/DebridCoreTests/OMDbRatingsCacheTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Packages/DebridCore/Tests/DebridCoreTests/OMDbRatingsCacheTests.swift`:

```swift
import Testing
import Foundation
@testable import DebridCore

struct OMDbRatingsCacheTests {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    }
    private let sample = OMDbRatings(imdb: 8.7, rottenTomatoes: 88, metacritic: 73)

    @Test func freshEntryIsReturned() async {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let cache = OMDbRatingsCache(directory: tempDir(), ttl: 100, now: { now })
        await cache.store(sample, imdbID: "tt1")
        #expect(await cache.cached(imdbID: "tt1") == sample)
    }

    @Test func expiredEntryNotReturnedByCached() async {
        var t = Date(timeIntervalSince1970: 1_000_000)
        let cache = OMDbRatingsCache(directory: tempDir(), ttl: 100, now: { t })
        await cache.store(sample, imdbID: "tt1")
        t = Date(timeIntervalSince1970: 1_000_200)   // 200s later, ttl is 100
        #expect(await cache.cached(imdbID: "tt1") == nil)
    }

    @Test func storedReturnsExpiredEntry() async {
        var t = Date(timeIntervalSince1970: 1_000_000)
        let cache = OMDbRatingsCache(directory: tempDir(), ttl: 100, now: { t })
        await cache.store(sample, imdbID: "tt1")
        t = Date(timeIntervalSince1970: 1_000_200)
        #expect(await cache.stored(imdbID: "tt1") == sample)   // stale, but available as fallback
    }

    @Test func missingEntryIsNil() async {
        let cache = OMDbRatingsCache(directory: tempDir(), ttl: 100, now: { Date() })
        #expect(await cache.cached(imdbID: "nope") == nil)
        #expect(await cache.stored(imdbID: "nope") == nil)
    }

    @Test func persistsAcrossInstances() async {
        let dir = tempDir()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let a = OMDbRatingsCache(directory: dir, ttl: 10_000, now: { now })
        await cacheStore(a, sample, "tt1")
        let b = OMDbRatingsCache(directory: dir, ttl: 10_000, now: { now })
        #expect(await b.cached(imdbID: "tt1") == sample)
    }

    // helper so the store write completes before we build the second instance
    private func cacheStore(_ c: OMDbRatingsCache, _ r: OMDbRatings, _ id: String) async {
        await c.store(r, imdbID: id)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path Packages/DebridCore --filter OMDbRatingsCacheTests`
Expected: FAIL — `OMDbRatingsCache` is not defined.

- [ ] **Step 3: Write the cache**

Create `Packages/DebridCore/Sources/DebridCore/Metadata/OMDbRatingsCache.swift`:

```swift
import Foundation

/// Persistent, TTL'd cache of OMDb ratings keyed by IMDb id, backed by one JSON file. Keeps us
/// well under OMDb's 1,000/day free quota: a given title costs ~1 fetch per TTL window. Reads
/// degrade silently (missing / unreadable file → empty), mirroring `LibrarySnapshotStore`.
public actor OMDbRatingsCache {
    struct Entry: Codable, Sendable {
        let ratings: OMDbRatings
        let fetchedAt: Date
    }

    private let directory: URL
    private let ttl: TimeInterval
    private let now: @Sendable () -> Date
    private var memory: [String: Entry]

    private var fileURL: URL { directory.appending(path: "omdb-ratings.json") }

    /// - Parameters:
    ///   - ttl: how long an entry stays "fresh" (default 7 days).
    ///   - now: injectable clock for testing.
    public init(directory: URL,
                ttl: TimeInterval = 7 * 24 * 60 * 60,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.directory = directory
        self.ttl = ttl
        self.now = now
        let url = directory.appending(path: "omdb-ratings.json")
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            self.memory = decoded
        } else {
            self.memory = [:]
        }
    }

    /// Fresh entry only (within TTL), else nil.
    public func cached(imdbID: String) -> OMDbRatings? {
        guard let entry = memory[imdbID], now().timeIntervalSince(entry.fetchedAt) < ttl else {
            return nil
        }
        return entry.ratings
    }

    /// Any stored entry regardless of age — the offline/stale fallback.
    public func stored(imdbID: String) -> OMDbRatings? { memory[imdbID]?.ratings }

    public func store(_ ratings: OMDbRatings, imdbID: String) {
        memory[imdbID] = Entry(ratings: ratings, fetchedAt: now())
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(memory) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --package-path Packages/DebridCore --filter OMDbRatingsCacheTests`
Expected: PASS (all 5 tests).

- [ ] **Step 5: Verify zero warnings**

Run: `swift build --package-path Packages/DebridCore 2>&1 | grep -i warning`
Expected: no output.

- [ ] **Step 6: Commit**

```bash
git add Packages/DebridCore/Sources/DebridCore/Metadata/OMDbRatingsCache.swift \
        Packages/DebridCore/Tests/DebridCoreTests/OMDbRatingsCacheTests.swift
git commit -m "feat(core): persistent 7-day OMDb ratings cache"
```

---

## Task 4: RatingsProviding seam + OMDbRatingsService (DebridUI)

**Files:**
- Create: `Shared/DebridUI/Sources/DebridUI/Detail/RatingsProviding.swift`
- Test: `Shared/DebridUI/Tests/DebridUITests/OMDbRatingsServiceTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Shared/DebridUI/Tests/DebridUITests/OMDbRatingsServiceTests.swift`:

```swift
import Testing
import Foundation
import DebridCore
@testable import DebridUI

struct OMDbRatingsServiceTests {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    }
    private let sample = OMDbRatings(imdb: 8.7, rottenTomatoes: 88, metacritic: 73)

    @Test func cacheMissFetchesAndStores() async throws {
        let cache = OMDbRatingsCache(directory: tempDir(), ttl: 10_000)
        let calls = Counter()
        let service = OMDbRatingsService(cache: cache, fetch: { _ in
            await calls.bump(); return self.sample
        })
        let r = try await service.ratings(imdbID: "tt1")
        #expect(r == sample)
        #expect(await calls.value == 1)
        // second call served from cache, no extra fetch
        _ = try await service.ratings(imdbID: "tt1")
        #expect(await calls.value == 1)
    }

    @Test func networkFailureFallsBackToStored() async throws {
        let cache = OMDbRatingsCache(directory: tempDir(), ttl: 0)   // everything is "stale" immediately
        await cache.store(sample, imdbID: "tt1")
        let service = OMDbRatingsService(cache: cache, fetch: { _ in
            throw OMDbError.notFound("boom")
        })
        let r = try await service.ratings(imdbID: "tt1")
        #expect(r == sample)   // stale fallback
    }

    @Test func failureWithNoEntryRethrows() async {
        let cache = OMDbRatingsCache(directory: tempDir(), ttl: 10_000)
        let service = OMDbRatingsService(cache: cache, fetch: { _ in
            throw OMDbError.notFound("boom")
        })
        await #expect(throws: OMDbError.self) { _ = try await service.ratings(imdbID: "tt1") }
    }

    private actor Counter {
        private(set) var value = 0
        func bump() { value += 1 }
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path Shared/DebridUI --filter OMDbRatingsServiceTests`
Expected: FAIL — `RatingsProviding` / `OMDbRatingsService` not defined.

- [ ] **Step 3: Write the seam + service**

Create `Shared/DebridUI/Sources/DebridUI/Detail/RatingsProviding.swift`:

```swift
import DebridCore

/// Thin Sendable seam over OMDb ratings, so `DetailStore` is unit-testable without the network.
/// Mirrors `MediaDetailsProviding`.
public protocol RatingsProviding: Sendable {
    func ratings(imdbID: String) async throws -> OMDbRatings
}

/// Production conformance: cache-first, with a stale-entry fallback when the network fails.
public struct OMDbRatingsService: RatingsProviding {
    private let cache: OMDbRatingsCache
    private let fetch: @Sendable (String) async throws -> OMDbRatings

    public init(client: OMDbClient, cache: OMDbRatingsCache) {
        self.cache = cache
        self.fetch = { try await client.ratings(imdbID: $0) }
    }

    /// Test seam: inject the fetch directly.
    init(cache: OMDbRatingsCache, fetch: @escaping @Sendable (String) async throws -> OMDbRatings) {
        self.cache = cache
        self.fetch = fetch
    }

    public func ratings(imdbID: String) async throws -> OMDbRatings {
        if let hit = await cache.cached(imdbID: imdbID) { return hit }
        do {
            let fresh = try await fetch(imdbID)
            await cache.store(fresh, imdbID: imdbID)
            return fresh
        } catch {
            if let stale = await cache.stored(imdbID: imdbID) { return stale }
            throw error
        }
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --package-path Shared/DebridUI --filter OMDbRatingsServiceTests`
Expected: PASS (all 3 tests).

- [ ] **Step 5: Verify zero warnings**

Run: `swift build --package-path Shared/DebridUI 2>&1 | grep -i warning`
Expected: no output.

- [ ] **Step 6: Commit**

```bash
git add Shared/DebridUI/Sources/DebridUI/Detail/RatingsProviding.swift \
        Shared/DebridUI/Tests/DebridUITests/OMDbRatingsServiceTests.swift
git commit -m "feat(ui): RatingsProviding seam + cache-first OMDbRatingsService"
```

---

## Task 5: Wire ratings into DetailStore (DebridUI)

**Files:**
- Modify: `Shared/DebridUI/Sources/DebridUI/Detail/DetailStore.swift`
- Test: `Shared/DebridUI/Tests/DebridUITests/RatingsDetailStoreTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Shared/DebridUI/Tests/DebridUITests/RatingsDetailStoreTests.swift`:

```swift
import Testing
import Foundation
import DebridCore
@testable import DebridUI

@MainActor
struct RatingsDetailStoreTests {
    // Minimal MediaDetailsProviding that returns a movie carrying an imdbID.
    struct StubDetails: MediaDetailsProviding {
        func movieDetails(tmdbID: Int) async throws -> TMDBMovieDetails {
            TMDBMovieDetails(id: tmdbID, title: "M", releaseDate: "2020-01-01", overview: "o",
                             posterPath: nil, backdropPath: nil, runtime: 100, genres: [],
                             voteAverage: 7.0, originalLanguage: "en", imdbID: "tt123")
        }
        func tvDetails(tmdbID: Int) async throws -> TMDBTVDetails { throw CancellationError() }
        func seasonEpisodes(tvID: Int, season: Int) async throws -> [TMDBEpisodeDetails] { [] }
    }
    struct OKRatings: RatingsProviding {
        let value: OMDbRatings
        func ratings(imdbID: String) async throws -> OMDbRatings { value }
    }
    struct FailRatings: RatingsProviding {
        func ratings(imdbID: String) async throws -> OMDbRatings { throw OMDbError.notFound("x") }
    }

    private func movie() -> MediaItem {
        MediaItem(id: "1", kind: .movie, title: "M", year: 2020, sources: [], seasons: [],
                  tmdbID: 99, overview: nil)
    }

    @Test func loadPopulatesRatings() async {
        let sample = OMDbRatings(imdb: 8.7, rottenTomatoes: 88, metacritic: 73)
        let store = DetailStore(item: movie(), details: StubDetails(), watch: nil,
                                ratings: OKRatings(value: sample))
        await store.load()
        #expect(store.ratings == sample)
        #expect(store.ratingsState == .loaded)
    }

    @Test func ratingsFailureDegradesGracefully() async {
        let store = DetailStore(item: movie(), details: StubDetails(), watch: nil,
                                ratings: FailRatings())
        await store.load()
        #expect(store.ratings == nil)
        #expect(store.ratingsState == .failed)
        #expect(store.richState == .loaded)   // the rest of the screen still loads
    }

    @Test func noProviderLeavesRatingsIdle() async {
        let store = DetailStore(item: movie(), details: StubDetails(), watch: nil)
        await store.load()
        #expect(store.ratings == nil)
        #expect(store.ratingsState == .idle)
    }
}
```

> NOTE: verify the `TMDBMovieDetails(...)` argument list against the public init at
> `Packages/DebridCore/Sources/DebridCore/Metadata/TMDBModels.swift:75`. If the parameter order
> differs, adjust the call — the test only needs a movie whose `imdbID == "tt123"`.

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path Shared/DebridUI --filter RatingsDetailStoreTests`
Expected: FAIL — `DetailStore.init` has no `ratings:` parameter; no `ratings`/`ratingsState`.

- [ ] **Step 3: Add the state, the provider, and the fetch**

In `Shared/DebridUI/Sources/DebridUI/Detail/DetailStore.swift`:

Add the stored provider next to the existing `details`/`watch` (after line 14):

```swift
    private let watch: WatchProgressProviding?
    private let ratingsProvider: RatingsProviding?
```

Add observable state after `numberOfSeasons` (after line 29):

```swift
    /// External ratings (IMDb / Rotten Tomatoes / Metacritic) from OMDb — supplemental, loaded
    /// after TMDB details resolve. nil until loaded (or if unavailable).
    public private(set) var ratings: OMDbRatings?
    public private(set) var ratingsState: RichState = .idle
```

Update the initializer (replace the existing `init`, lines 31-38):

```swift
    public init(item: MediaItem, details: MediaDetailsProviding, watch: WatchProgressProviding?,
                ratings: RatingsProviding? = nil) {
        self.item = item
        self.details = details
        self.watch = watch
        self.ratingsProvider = ratings
        self.overview = item.overview
        self.backdropPath = item.backdropPath
        self.selectedSeason = item.seasons.first?.number ?? 1
    }
```

In `load()`, add the ratings fetch immediately after `richState = .loaded` (currently line 106):

```swift
            richState = .loaded
            await loadRatings()
```

Add the private helper in the `// MARK: - Private` section (e.g. after `loadSeason`):

```swift
    /// Supplemental, non-blocking: enrich with OMDb ratings once TMDB has given us the IMDb id.
    /// Failure leaves `ratings == nil` and the rest of the screen intact.
    private func loadRatings() async {
        guard let provider = ratingsProvider, let imdb = imdbID else { return }
        ratingsState = .loading
        do {
            ratings = try await provider.ratings(imdbID: imdb)
            ratingsState = .loaded
        } catch {
            ratingsState = .failed
        }
    }
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --package-path Shared/DebridUI --filter RatingsDetailStoreTests`
Expected: PASS (all 3 tests).

- [ ] **Step 5: Run the full DebridUI + DebridCore suites (no regressions)**

Run: `swift test --package-path Shared/DebridUI && swift test --package-path Packages/DebridCore`
Expected: all green (existing `DetailStoreTests` still pass — the new `ratings:` param is defaulted).

- [ ] **Step 6: Verify zero warnings**

Run: `swift build --package-path Shared/DebridUI 2>&1 | grep -i warning`
Expected: no output.

- [ ] **Step 7: Commit**

```bash
git add Shared/DebridUI/Sources/DebridUI/Detail/DetailStore.swift \
        Shared/DebridUI/Tests/DebridUITests/RatingsDetailStoreTests.swift
git commit -m "feat(ui): DetailStore loads OMDb ratings after TMDB details"
```

---

## Task 6: Secrets plumbing (OMDB_API_KEY)

**Files:**
- Modify: `Shared/DebridUI/Sources/DebridUI/Support/Secrets.swift`
- Modify: `Secrets.example.xcconfig`
- Modify: `Secrets.xcconfig` (gitignored — local only)
- Modify: `project.yml`

No automated test (build-time config). Verified by compile + the app reading the key.

- [ ] **Step 1: Add the accessor**

In `Shared/DebridUI/Sources/DebridUI/Support/Secrets.swift`, add after `openSubtitlesAPIKey` (after line 17):

```swift

    /// OMDb API key: `OMDB_API_KEY` (Secrets.xcconfig) → `OMDBAPIKey` (Info.plist) → here.
    /// Empty string when unset — callers treat empty as "ratings unavailable."
    public static var omdbAPIKey: String {
        (Bundle.main.object(forInfoDictionaryKey: "OMDBAPIKey") as? String) ?? ""
    }
```

- [ ] **Step 2: Add the example placeholder**

In `Secrets.example.xcconfig`, add a line:

```
OMDB_API_KEY =
```

- [ ] **Step 3: Add the real key line locally**

In `Secrets.xcconfig` (gitignored), add:

```
OMDB_API_KEY =
```

> The owner pastes a free key from omdbapi.com/apikey.aspx here. An empty value keeps ratings
> off by design (no crash) — exactly like the OpenSubtitles key.

- [ ] **Step 4: Map the key into both Info.plists**

In `project.yml`, add `OMDBAPIKey` next to the existing two keys in BOTH app targets:

After line 39 (SeretTV):
```yaml
        OMDBAPIKey: "$(OMDB_API_KEY)"
```
After line 97 (SeretMobile):
```yaml
        OMDBAPIKey: "$(OMDB_API_KEY)"
```

> Verify with: `grep -n "OMDBAPIKey\|OpenSubtitlesAPIKey" project.yml` — there should be two of each.

- [ ] **Step 5: Regenerate the project + verify it builds**

Run: `cd /Users/shaharsolomons/Documents/Code/Seret && xcodegen generate`
Then: `swift build --package-path Shared/DebridUI 2>&1 | grep -i warning`
Expected: no warning output; `xcodegen` succeeds.

- [ ] **Step 6: Commit (do NOT stage project.yml if the owner has unrelated edits there — check first)**

```bash
git status --short project.yml   # if it shows ONLY the OMDBAPIKey additions, stage it; else stage with care
git add Shared/DebridUI/Sources/DebridUI/Support/Secrets.swift Secrets.example.xcconfig project.yml
git commit -m "feat: OMDB_API_KEY secret plumbing"
```

> `Secrets.xcconfig` is gitignored — it is intentionally NOT committed.

---

## Task 7: Compose ratingsProvider in AppSession + thread to the detail screens

**Files:**
- Modify: `Shared/DebridUI/Sources/DebridUI/Shell/AppSession.swift`
- Modify: `Apps/SeretMobile/Detail/DetailScreen.swift`
- Modify: `Apps/SeretTV/Detail/DetailView.swift`
- Modify: `Apps/SeretMobile/Shell/RootView.swift`
- Modify: `Apps/SeretTV/Shell/LibraryShell.swift`

No new unit test (composition glue); verified by the existing DetailStore tests + app build.

- [ ] **Step 1: Add the vended property to AppSession**

In `Shared/DebridUI/Sources/DebridUI/Shell/AppSession.swift`, add after `detailsProvider` (after line 34):

```swift

    /// On-demand OMDb ratings provider for the Detail screen (nil while signed out or no key).
    public private(set) var ratingsProvider: RatingsProviding?
```

- [ ] **Step 2: Reset it on sign-out**

In `enterSignedOut()`, add next to `detailsProvider = nil` (after line 130):

```swift
        ratingsProvider = nil
```

- [ ] **Step 3: Compose it on sign-in**

In `enterSignedIn()`, add immediately after `detailsProvider = TMDBDetailsService(client: tmdb)` (line 214):

```swift
        let omdbKey = Secrets.omdbAPIKey
        ratingsProvider = omdbKey.isEmpty ? nil
            : OMDbRatingsService(client: OMDbClient(apiKey: omdbKey),
                                 cache: OMDbRatingsCache(directory: Self.cachesDirectory))
```

- [ ] **Step 4: Add the `ratings:` parameter to DetailScreen (mobile)**

In `Apps/SeretMobile/Detail/DetailScreen.swift`, replace the initializer (lines 21-23):

```swift
    init(item: MediaItem, details: MediaDetailsProviding, watch: WatchProgressProviding?,
         ratings: RatingsProviding? = nil) {
        _store = State(initialValue: DetailStore(item: item, details: details, watch: watch,
                                                 ratings: ratings))
    }
```

- [ ] **Step 5: Add the `ratings:` parameter to DetailView (tvOS)**

In `Apps/SeretTV/Detail/DetailView.swift`, replace the initializer (lines 18-20):

```swift
    init(item: MediaItem, details: MediaDetailsProviding, watch: WatchProgressProviding?,
         ratings: RatingsProviding? = nil) {
        _store = State(initialValue: DetailStore(item: item, details: details, watch: watch,
                                                 ratings: ratings))
    }
```

- [ ] **Step 6: Pass the provider from the mobile call site**

In `Apps/SeretMobile/Shell/RootView.swift:26`, change:

```swift
                DetailScreen(item: item, details: details, watch: session.watchStore)
```
to:
```swift
                DetailScreen(item: item, details: details, watch: session.watchStore,
                             ratings: session.ratingsProvider)
```

- [ ] **Step 7: Pass the provider from the tvOS call site**

In `Apps/SeretTV/Shell/LibraryShell.swift:30`, change:

```swift
                            DetailView(item: item, details: details, watch: session.watchStore)
```
to:
```swift
                            DetailView(item: item, details: details, watch: session.watchStore,
                                       ratings: session.ratingsProvider)
```

- [ ] **Step 8: Verify DebridUI builds + tests stay green**

Run: `swift build --package-path Shared/DebridUI 2>&1 | grep -i warning && swift test --package-path Shared/DebridUI`
Expected: no warning output; all tests pass.

- [ ] **Step 9: Commit**

```bash
git add Shared/DebridUI/Sources/DebridUI/Shell/AppSession.swift \
        Apps/SeretMobile/Detail/DetailScreen.swift Apps/SeretTV/Detail/DetailView.swift \
        Apps/SeretMobile/Shell/RootView.swift Apps/SeretTV/Shell/LibraryShell.swift
git commit -m "feat: compose + inject OMDb ratings provider into detail screens"
```

---

## Task 8: RatingsRow + placement — SeretMobile

**Files:**
- Create: `Apps/SeretMobile/Detail/RatingsRow.swift`
- Modify: `Apps/SeretMobile/Detail/MovieDetail.swift`
- Modify: `Apps/SeretMobile/Detail/ShowDetail.swift`

SwiftUI view — no unit-test infra in this repo (same as `QualityChipRow`); verified by the sim screenshot in Task 10.

- [ ] **Step 1: Create the view**

Create `Apps/SeretMobile/Detail/RatingsRow.swift`:

```swift
import DebridCore
import DebridUI
import SwiftUI

/// IMDb / Rotten Tomatoes / Metacritic badges from OMDb. Renders only the scores that exist;
/// the whole row disappears when there are none (or ratings haven't loaded).
struct RatingsRow: View {
    let ratings: OMDbRatings?

    var body: some View {
        if let r = ratings, r.hasAny {
            HStack(spacing: Theme.Space.lg) {
                if let imdb = r.imdb { badge("⭐", "IMDb \(String(format: "%.1f", imdb))") }
                if let rt = r.rottenTomatoes { badge("🍅", "\(rt)%") }
                if let mc = r.metacritic { badge("Ⓜ", "\(mc)") }
            }
        }
    }

    private func badge(_ icon: String, _ text: String) -> some View {
        Text("\(icon) \(text)")
            .font(Theme.Typo.caption())
            .foregroundStyle(Theme.Palette.textSecondary)
    }
}
```

- [ ] **Step 2: Place it in MovieDetail**

In `Apps/SeretMobile/Detail/MovieDetail.swift`, add right after the quality chip row (line 25):

```swift
                if let best = store.bestSource { QualityChipRow(parsed: best.parsed) }
                RatingsRow(ratings: store.ratings)
```

- [ ] **Step 3: Place it in ShowDetail**

In `Apps/SeretMobile/Detail/ShowDetail.swift`, add right after the meta line (line 31):

```swift
                Text(metaLine).font(Theme.Typo.body()).foregroundStyle(Theme.Palette.textSecondary)
                RatingsRow(ratings: store.ratings)
```

- [ ] **Step 4: Build SeretMobile**

Run:
```bash
cd /Users/shaharsolomons/Documents/Code/Seret && xcodegen generate && \
xcodebuild -scheme SeretMobile -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Apps/SeretMobile/Detail/RatingsRow.swift \
        Apps/SeretMobile/Detail/MovieDetail.swift Apps/SeretMobile/Detail/ShowDetail.swift
git commit -m "feat(mobile): show OMDb ratings row on movie + show detail"
```

---

## Task 9: RatingsRow + placement — SeretTV

**Files:**
- Create: `Apps/SeretTV/Detail/RatingsRow.swift`
- Modify: `Apps/SeretTV/Detail/MovieDetailView.swift`
- Modify: `Apps/SeretTV/Detail/ShowDetailView.swift`

- [ ] **Step 1: Create the view**

Create `Apps/SeretTV/Detail/RatingsRow.swift`:

```swift
import DebridCore
import DebridUI
import SwiftUI

/// IMDb / Rotten Tomatoes / Metacritic badges from OMDb (tvOS). Renders only the scores that
/// exist; the whole row disappears when there are none (or ratings haven't loaded).
struct RatingsRow: View {
    let ratings: OMDbRatings?

    var body: some View {
        if let r = ratings, r.hasAny {
            HStack(spacing: 24) {
                if let imdb = r.imdb { Text("⭐ IMDb \(String(format: "%.1f", imdb))") }
                if let rt = r.rottenTomatoes { Text("🍅 \(rt)%") }
                if let mc = r.metacritic { Text("Ⓜ \(mc)") }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }
}
```

- [ ] **Step 2: Place it in MovieDetailView**

In `Apps/SeretTV/Detail/MovieDetailView.swift`, add right after the quality chips (line 39):

```swift
            if let best = store.bestSource { QualityChips(parsed: best.parsed) }
            RatingsRow(ratings: store.ratings)
```

- [ ] **Step 3: Place it in ShowDetailView**

In `Apps/SeretTV/Detail/ShowDetailView.swift`, add right after the meta line (line 57):

```swift
            Text(metaLine).font(.body).foregroundStyle(.secondary)
            RatingsRow(ratings: store.ratings)
```

- [ ] **Step 4: Build SeretTV**

Run:
```bash
cd /Users/shaharsolomons/Documents/Code/Seret && xcodegen generate && \
xcodebuild -scheme SeretTV -destination 'generic/platform=tvOS Simulator' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Apps/SeretTV/Detail/RatingsRow.swift \
        Apps/SeretTV/Detail/MovieDetailView.swift Apps/SeretTV/Detail/ShowDetailView.swift
git commit -m "feat(tv): show OMDb ratings row on movie + show detail"
```

---

## Task 10: Full verification

**Files:** none (verification only).

- [ ] **Step 1: Run the full brain suite**

Run: `swift test --package-path Packages/DebridCore`
Expected: all green (includes the new OMDb client + cache tests). Note the new total count.

- [ ] **Step 2: Run the full shared-UI suite**

Run: `swift test --package-path Shared/DebridUI`
Expected: all green (includes the new service + DetailStore ratings tests).

- [ ] **Step 3: Zero-warning check across both packages**

Run:
```bash
swift build --package-path Packages/DebridCore 2>&1 | grep -i warning
swift build --package-path Shared/DebridUI 2>&1 | grep -i warning
```
Expected: no output from either.

- [ ] **Step 4: Build both apps**

Run:
```bash
cd /Users/shaharsolomons/Documents/Code/Seret && xcodegen generate
xcodebuild -scheme SeretMobile -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -3
xcodebuild -scheme SeretTV -destination 'generic/platform=tvOS Simulator' build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **` for both.

- [ ] **Step 5: Owner-pending verification (note in the handoff, do not block on it)**

The ratings ROW is verified visually by the owner in the simulator (this dev env can't launch the
tvOS sim — see CLAUDE.md Gotchas), after he:
1. Pastes a free OMDb key into `Secrets.xcconfig` (`OMDB_API_KEY = …`, from omdbapi.com/apikey.aspx).
2. Signs in with his RD token and opens a movie/show detail.
3. Confirms `⭐ IMDb · 🍅 % · Ⓜ` appears below the quality chips and screenshots it.

Until the key is set, the row is correctly absent (empty key ⇒ no provider ⇒ no ratings).

---

## Self-Review Notes

- **Spec coverage:** OMDbClient (T2), model+RT/Metacritic/IMDb mapping (T1), seam+service+cache-first+stale fallback (T3,T4), DetailStore non-blocking wiring (T5), Secrets (T6), AppSession compose + empty-key=off (T7), per-app RatingsRow below chips/meta (T8,T9), all "all three" ratings, 7-day cache. ✓
- **Types:** `OMDbRatings`, `OMDbResponse`, `OMDbError`, `OMDbClient.ratings(imdbID:)`, `OMDbRatingsCache.cached/stored/store`, `RatingsProviding.ratings(imdbID:)`, `OMDbRatingsService.init(client:cache:)` + test `init(cache:fetch:)`, `DetailStore.init(...,ratings:)`, `DetailStore.ratings`/`ratingsState`, `AppSession.ratingsProvider` — names consistent across tasks. ✓
- **Watch-outs:** (1) verify `TMDBMovieDetails` init arg order at TMDBModels.swift:75 when writing the T5 test. (2) Stage `project.yml` carefully in T6 — owner has parallel edits. (3) tvOS sim can't launch here; app verification is `xcodebuild build` + owner screenshots.
