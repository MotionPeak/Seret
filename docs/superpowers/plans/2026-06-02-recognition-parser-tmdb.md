# Recognition Primitives: FilenameParser + TMDBClient — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give `DebridCore` the two building blocks of "recognize & organize": a `FilenameParser` that turns a release name into structured fields, and a `TMDBClient` that looks up movies/shows and their artwork. (Assembling these + RD torrents into an organized library is Plan 4.)

**Architecture:** `FilenameParser` is pure, dependency-free string logic — metadata fields are matched by regex on the original (dotted) release name; the title is taken by walking tokens until the first metadata token. `TMDBClient` is a value type over the existing `HTTPClient`, taking an injected API key (TMDB v3 `api_key` query param); tests mock all responses, so **no real key is needed to build or test this plan** (the key is supplied at app-wiring time). Everything unit-tested with Swift Testing.

**Tech Stack:** Swift 6.3 (Swift 6 language mode), SPM, async/await, Swift Testing, `Foundation` regex (`NSRegularExpression`).

**Plan 3 of the Seret roadmap.** Next: Plan 4 — `LibraryBuilder` (parser + TMDB + RD torrents → organized Movies/Shows library).

> **Parser note for the implementer:** release-name parsing is inherently fuzzy. The Task 1 test table IS the contract — implement the parser to make every case green, adjusting the provided regex/logic as needed. Known v1 limitations (e.g. a year-like number inside a title such as "Blade Runner 2049") are intentionally NOT in the table and will be refined later.

---

## File Structure

| File | Responsibility |
|---|---|
| `Sources/DebridCore/Metadata/ParsedRelease.swift` | `ParsedRelease` value type (structured fields from a release name) |
| `Sources/DebridCore/Metadata/FilenameParser.swift` | Pure parser: release name → `ParsedRelease` |
| `Sources/DebridCore/Metadata/TMDBModels.swift` | `TMDBSearchResult`, `TMDBMovieDetails`, `TMDBTVDetails`, `TMDBGenre` |
| `Sources/DebridCore/Metadata/TMDBClient.swift` | Search + details + image-URL helper |
| `Tests/DebridCoreTests/FilenameParserTests.swift` | Parser table (movies + TV) — pure, plain suite |
| `Tests/DebridCoreTests/TMDBClientTests.swift` | Search + details (nested under `MockTests` — uses the network mock) |

---

## Task 1: FilenameParser

**Files:**
- Create: `Packages/DebridCore/Sources/DebridCore/Metadata/ParsedRelease.swift`
- Create: `Packages/DebridCore/Sources/DebridCore/Metadata/FilenameParser.swift`
- Create: `Packages/DebridCore/Tests/DebridCoreTests/FilenameParserTests.swift`

- [ ] **Step 1: Write the failing test table** (pure suite — NOT nested under `MockTests`)

`Tests/DebridCoreTests/FilenameParserTests.swift`:
```swift
import Testing
@testable import DebridCore

struct FilenameParserTests {
    let parser = FilenameParser()

    // MARK: Movies
    @Test func parsesA4KBluRayMovie() {
        let r = parser.parse("Dune.Part.Two.2024.2160p.UHD.BluRay.x265-WiKi.mkv")
        #expect(r.title == "Dune Part Two")
        #expect(r.year == 2024)
        #expect(r.resolution == "2160p")
        #expect(r.source == "BluRay")
        #expect(r.videoCodec == "x265")
        #expect(r.releaseGroup == "WiKi")
        #expect(r.season == nil)
        #expect(r.episode == nil)
        #expect(r.isTV == false)
    }

    @Test func parsesAWebDLMovieWithAudio() {
        let r = parser.parse("Oppenheimer.2023.1080p.WEB-DL.DDP5.1.H264-EVO.mkv")
        #expect(r.title == "Oppenheimer")
        #expect(r.year == 2023)
        #expect(r.resolution == "1080p")
        #expect(r.source == "WEB-DL")
        #expect(r.videoCodec == "h264")
        #expect(r.audioCodec == "DDP5.1")
        #expect(r.releaseGroup == "EVO")
    }

    @Test func parsesSpaceSeparatedMovie() {
        let r = parser.parse("The Batman 2022 720p BluRay x264.mp4")
        #expect(r.title == "The Batman")
        #expect(r.year == 2022)
        #expect(r.resolution == "720p")
        #expect(r.videoCodec == "x264")
    }

    // MARK: TV
    @Test func parsesStandardEpisode() {
        let r = parser.parse("Shogun.S01E03.1080p.WEB-DL.DDP5.1.x265-NTb.mkv")
        #expect(r.title == "Shogun")
        #expect(r.season == 1)
        #expect(r.episode == 3)
        #expect(r.isTV == true)
        #expect(r.resolution == "1080p")
    }

    @Test func parsesXFormatEpisode() {
        let r = parser.parse("Severance.2x05.720p.HDTV.x264-GROUP.mkv")
        #expect(r.title == "Severance")
        #expect(r.season == 2)
        #expect(r.episode == 5)
        #expect(r.source == "HDTV")
    }

    @Test func parsesSeasonPack() {
        let r = parser.parse("Fallout.S01.2160p.AMZN.WEB-DL.DDP5.1.HDR.HEVC-FLUX")
        #expect(r.title == "Fallout")
        #expect(r.season == 1)
        #expect(r.episode == nil)   // season pack — no single episode
        #expect(r.isTV == true)
        #expect(r.videoCodec == "HEVC")
    }

    @Test func extractsTitleFromDottedNameWithNoYear() {
        let r = parser.parse("Some.Indie.Documentary.1080p.WEBRip.x264-AAA.mkv")
        #expect(r.title == "Some Indie Documentary")
        #expect(r.year == nil)
        #expect(r.resolution == "1080p")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path Packages/DebridCore --filter FilenameParserTests`
Expected: FAIL — `FilenameParser` / `ParsedRelease` not defined.

- [ ] **Step 3: Implement `ParsedRelease.swift`**

```swift
/// Structured fields extracted from a release name. All optional except `title`.
public struct ParsedRelease: Sendable, Equatable {
    public var title: String
    public var year: Int?
    public var season: Int?
    public var episode: Int?
    public var resolution: String?
    public var source: String?
    public var videoCodec: String?
    public var audioCodec: String?
    public var releaseGroup: String?

    public init(title: String, year: Int? = nil, season: Int? = nil, episode: Int? = nil,
                resolution: String? = nil, source: String? = nil, videoCodec: String? = nil,
                audioCodec: String? = nil, releaseGroup: String? = nil) {
        self.title = title; self.year = year; self.season = season; self.episode = episode
        self.resolution = resolution; self.source = source; self.videoCodec = videoCodec
        self.audioCodec = audioCodec; self.releaseGroup = releaseGroup
    }

    /// A release is "TV" if it carries a season or episode number.
    public var isTV: Bool { season != nil || episode != nil }
}
```

- [ ] **Step 4: Implement `FilenameParser.swift`** (make the Step 1 table green — adjust regex if a case fails)

```swift
import Foundation

/// Turns a release filename into a `ParsedRelease`. Pure and dependency-free.
/// Metadata fields are matched by regex on the original (dotted) name; the title is
/// the run of leading tokens before the first metadata token.
public struct FilenameParser: Sendable {
    public init() {}

    public func parse(_ raw: String) -> ParsedRelease {
        let name = String(raw.split(separator: "/").last ?? Substring(raw))
        let stem = Self.stripExtension(name)

        let releaseGroup = Self.capture(stem, #"-([A-Za-z0-9]{2,})$"#)
        let resolution = Self.match(stem, #"(?i)\b(2160p|1080p|720p|480p)\b"#)?.lowercased()
        let source = Self.normalizeSource(Self.match(stem, #"(?i)\b(blu-?ray|bd-?rip|web-?dl|web-?rip|hdtv|dvd-?rip|remux|hdrip)\b"#))
        let videoCodec = Self.normalizeVideo(Self.match(stem, #"(?i)\b(x265|x264|h\.?265|h\.?264|hevc|avc)\b"#))
        let audioCodec = Self.normalizeAudio(Self.match(stem, #"(?i)\b(dts-?hd|truehd|atmos|ddp?5\.1|ddp|dts|eac3|ac3|aac|flac)\b"#))
        let year = Self.match(stem, #"\b(19\d{2}|20\d{2})\b"#).flatMap { Int($0) }

        var season: Int?
        var episode: Int?
        if let g = Self.captures(stem, #"(?i)\bS(\d{1,2})E(\d{1,3})\b"#) {
            season = Int(g[0]); episode = Int(g[1])
        } else if let g = Self.captures(stem, #"(?i)\b(\d{1,2})x(\d{1,3})\b"#) {
            season = Int(g[0]); episode = Int(g[1])
        } else if let g = Self.captures(stem, #"(?i)\bseason\s?(\d{1,2})\b"#) {
            season = Int(g[0])
        } else if let g = Self.captures(stem, #"(?i)\bS(\d{1,2})\b"#) {
            season = Int(g[0])
        }

        return ParsedRelease(
            title: Self.extractTitle(stem),
            year: year, season: season, episode: episode,
            resolution: resolution, source: source, videoCodec: videoCodec,
            audioCodec: audioCodec, releaseGroup: releaseGroup)
    }

    // MARK: - Title

    private static func extractTitle(_ stem: String) -> String {
        let tokens = stem.split(whereSeparator: { $0 == "." || $0 == "_" || $0 == " " }).map(String.init)
        var titleTokens: [String] = []
        for token in tokens {
            if isMetadataToken(token) { break }
            titleTokens.append(token)
        }
        let joined = titleTokens.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return joined.isEmpty ? stem : joined
    }

    private static func isMetadataToken(_ t: String) -> Bool {
        let patterns = [
            #"^(19|20)\d{2}$"#,
            #"(?i)^s\d{1,2}e\d{1,3}$"#,
            #"(?i)^s\d{1,2}$"#,
            #"(?i)^\d{1,2}x\d{1,3}$"#,
            #"(?i)^(2160p|1080p|720p|480p)$"#,
            #"(?i)^season$"#,
            #"(?i)^(bluray|blu-ray|bdrip|web-?dl|web-?rip|hdtv|dvdrip|remux|hdrip|x265|x264|h264|h265|hevc|avc|amzn|uhd|hdr)$"#,
        ]
        return patterns.contains { t.range(of: $0, options: .regularExpression) != nil }
    }

    // MARK: - Normalization (canonical display forms)

    private static func normalizeSource(_ s: String?) -> String? {
        guard let s = s?.lowercased() else { return nil }
        if s.hasPrefix("blu") { return "BluRay" }
        if s.replacingOccurrences(of: "-", with: "") == "webdl" { return "WEB-DL" }
        if s.replacingOccurrences(of: "-", with: "") == "webrip" { return "WEBRip" }
        if s.contains("remux") { return "REMUX" }
        if s.contains("hdtv") { return "HDTV" }
        if s.contains("bd") { return "BDRip" }
        if s.contains("dvd") { return "DVDRip" }
        if s.contains("hdrip") { return "HDRip" }
        return s.uppercased()
    }

    private static func normalizeVideo(_ s: String?) -> String? {
        guard let s = s?.lowercased().replacingOccurrences(of: ".", with: "") else { return nil }
        switch s {
        case "x265": return "x265"
        case "x264": return "x264"
        case "h265", "hevc": return s == "hevc" ? "HEVC" : "h265"
        case "h264", "avc": return s == "avc" ? "AVC" : "h264"
        default: return s
        }
    }

    private static func normalizeAudio(_ s: String?) -> String? {
        guard let raw = s else { return nil }
        let s = raw.lowercased()
        if s.replacingOccurrences(of: "-", with: "") == "dtshd" { return "DTS-HD" }
        if s.hasPrefix("ddp") { return "DDP5.1" }
        if s == "truehd" { return "TrueHD" }
        if s == "atmos" { return "Atmos" }
        if s == "eac3" { return "EAC3" }
        if s == "ac3" { return "AC3" }
        if s == "aac" { return "AAC" }
        if s == "flac" { return "FLAC" }
        if s == "dts" { return "DTS" }
        return raw.uppercased()
    }

    // MARK: - Regex helpers

    private static func stripExtension(_ s: String) -> String {
        let exts: Set<String> = ["mkv", "mp4", "avi", "m4v", "mov", "ts", "wmv", "srt", "ass"]
        guard let dot = s.range(of: #"\.[A-Za-z0-9]{2,4}$"#, options: .regularExpression) else { return s }
        let ext = s[dot].dropFirst().lowercased()
        return exts.contains(String(ext)) ? String(s[s.startIndex..<dot.lowerBound]) : s
    }

    /// Returns the full first match of `pattern` in `s` (group 0), or nil.
    private static func match(_ s: String, _ pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let r = Range(m.range, in: s) else { return nil }
        return String(s[r])
    }

    /// Returns capture group 1 of the first match, or nil.
    private static func capture(_ s: String, _ pattern: String) -> String? {
        captures(s, pattern)?.first
    }

    /// Returns all capture groups (1...n) of the first match, or nil if no match.
    private static func captures(_ s: String, _ pattern: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              m.numberOfRanges > 1 else { return nil }
        var groups: [String] = []
        for i in 1..<m.numberOfRanges {
            guard let r = Range(m.range(at: i), in: s) else { return nil }
            groups.append(String(s[r]))
        }
        return groups
    }
}
```

- [ ] **Step 5: Run the table; iterate regex until green**

Run: `swift test --package-path Packages/DebridCore --filter FilenameParserTests`
Expected: PASS (7 tests). If any case fails, adjust the regex/normalization to satisfy the table (the table is the contract). Then full suite `swift test --package-path Packages/DebridCore` → 35 tests. Confirm `swift build … | grep -i warning` is empty.

- [ ] **Step 6: Commit**

```bash
git add Packages/DebridCore
git commit -m "feat(core): FilenameParser — release name → structured ParsedRelease"
```

---

## Task 2: TMDBClient — search

**Files:**
- Create: `Packages/DebridCore/Sources/DebridCore/Metadata/TMDBModels.swift`
- Create: `Packages/DebridCore/Sources/DebridCore/Metadata/TMDBClient.swift`
- Create: `Packages/DebridCore/Tests/DebridCoreTests/TMDBClientTests.swift`

- [ ] **Step 1: Write the failing test** (nested under `MockTests` — uses the network mock)

`Tests/DebridCoreTests/TMDBClientTests.swift`:
```swift
import Testing
import Foundation
@testable import DebridCore

extension MockTests {
    @Suite struct TMDBClientTests {
        init() { MockURLProtocol.handler = nil }

        @Test func searchesMovies() async throws {
            MockURLProtocol.stub(status: 200, json: #"""
            {"page":1,"results":[
              {"id":693134,"title":"Dune: Part Two","release_date":"2024-02-27",
               "poster_path":"/poster.jpg","overview":"Paul…","vote_average":8.3}],
             "total_results":1}
            """#)
            let client = TMDBClient(apiKey: "KEY", http: HTTPClient(session: .mock))
            let results = try await client.searchMovie(query: "Dune Part Two", year: 2024)
            #expect(results.count == 1)
            #expect(results[0].id == 693134)
            #expect(results[0].displayTitle == "Dune: Part Two")
            #expect(results[0].year == 2024)
        }

        @Test func searchesTV() async throws {
            MockURLProtocol.stub(status: 200, json: #"""
            {"page":1,"results":[
              {"id":110492,"name":"Shōgun","first_air_date":"2024-02-27",
               "poster_path":"/s.jpg","overview":"…","vote_average":8.7}],
             "total_results":1}
            """#)
            let client = TMDBClient(apiKey: "KEY", http: HTTPClient(session: .mock))
            let results = try await client.searchTV(query: "Shogun", firstAirYear: 2024)
            #expect(results[0].displayTitle == "Shōgun")
            #expect(results[0].year == 2024)
        }
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path Packages/DebridCore --filter TMDBClientTests`
Expected: FAIL — `TMDBClient` / `TMDBSearchResult` not defined.

- [ ] **Step 3: Implement `TMDBModels.swift`**

```swift
import Foundation

/// A row from a TMDB `/search/movie` or `/search/tv` response.
public struct TMDBSearchResult: Decodable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let title: String?          // movies
    public let name: String?           // tv
    public let releaseDate: String?    // movies, "YYYY-MM-DD"
    public let firstAirDate: String?   // tv
    public let posterPath: String?
    public let overview: String?
    public let voteAverage: Double?

    enum CodingKeys: String, CodingKey {
        case id, title, name, overview
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
        case posterPath = "poster_path"
        case voteAverage = "vote_average"
    }

    /// Movie `title` or TV `name`.
    public var displayTitle: String { title ?? name ?? "" }

    /// Year parsed from the release / first-air date (the leading 4 digits).
    public var year: Int? {
        let date = releaseDate ?? firstAirDate
        guard let prefix = date?.prefix(4) else { return nil }
        return Int(prefix)
    }
}

/// Internal envelope for `/search/*` responses. `internal` (not `private`) so
/// `TMDBClient` — same module, different file — can decode into it.
struct TMDBSearchResponse: Decodable { let results: [TMDBSearchResult] }

public struct TMDBGenre: Decodable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let name: String
}

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

    enum CodingKeys: String, CodingKey {
        case id, title, overview, runtime, genres
        case releaseDate = "release_date"
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case voteAverage = "vote_average"
    }
}

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

    enum CodingKeys: String, CodingKey {
        case id, name, overview, genres
        case firstAirDate = "first_air_date"
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case numberOfSeasons = "number_of_seasons"
        case voteAverage = "vote_average"
    }
}
```

(`TMDBSearchResponse` above is declared `internal`, so `TMDBClient` — same module, different file — decodes `/search/*` responses into it.)

- [ ] **Step 4: Implement `TMDBClient.swift`**

```swift
import Foundation

/// Looks up movies/shows on TMDB (v3 API, `api_key` query param). The key is injected;
/// tests mock the transport, so no real key is needed to test.
public struct TMDBClient: Sendable {
    public static let base = URL(string: "https://api.themoviedb.org/3")!
    public static let imageBase = "https://image.tmdb.org/t/p/"

    private let apiKey: String
    private let http: HTTPClient

    public init(apiKey: String, http: HTTPClient = HTTPClient()) {
        self.apiKey = apiKey
        self.http = http
    }

    public func searchMovie(query: String, year: Int? = nil) async throws -> [TMDBSearchResult] {
        var items = [URLQueryItem(name: "query", value: query)]
        if let year { items.append(.init(name: "year", value: String(year))) }
        let response: TMDBSearchResponse = try await get("search/movie", items)
        return response.results
    }

    public func searchTV(query: String, firstAirYear: Int? = nil) async throws -> [TMDBSearchResult] {
        var items = [URLQueryItem(name: "query", value: query)]
        if let firstAirYear { items.append(.init(name: "first_air_date_year", value: String(firstAirYear))) }
        let response: TMDBSearchResponse = try await get("search/tv", items)
        return response.results
    }

    private func get<T: Decodable>(_ path: String, _ items: [URLQueryItem]) async throws -> T {
        var comps = URLComponents(url: Self.base.appending(path: path), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "api_key", value: apiKey)] + items
        return try await http.get(comps.url!)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --package-path Packages/DebridCore --filter TMDBClientTests`
Expected: PASS (2 tests). Full suite → 37 tests. No warnings.

- [ ] **Step 6: Commit**

```bash
git add Packages/DebridCore
git commit -m "feat(core): TMDBClient search (movie/tv) + TMDB models"
```

---

## Task 3: TMDBClient — details + poster URLs

**Files:**
- Modify: `Packages/DebridCore/Sources/DebridCore/Metadata/TMDBClient.swift`
- Modify: `Packages/DebridCore/Tests/DebridCoreTests/TMDBClientTests.swift`

- [ ] **Step 1: Write the failing tests** (add inside the existing `TMDBClientTests` struct)

```swift
        @Test func fetchesMovieDetails() async throws {
            MockURLProtocol.stub(status: 200, json: #"""
            {"id":693134,"title":"Dune: Part Two","release_date":"2024-02-27",
             "overview":"Paul…","poster_path":"/p.jpg","backdrop_path":"/b.jpg",
             "runtime":166,"vote_average":8.3,
             "genres":[{"id":878,"name":"Science Fiction"},{"id":12,"name":"Adventure"}]}
            """#)
            let client = TMDBClient(apiKey: "KEY", http: HTTPClient(session: .mock))
            let details = try await client.movieDetails(id: 693134)
            #expect(details.title == "Dune: Part Two")
            #expect(details.runtime == 166)
            #expect(details.genres.count == 2)
            #expect(details.genres[0].name == "Science Fiction")
        }

        @Test func fetchesTVDetails() async throws {
            MockURLProtocol.stub(status: 200, json: #"""
            {"id":110492,"name":"Shōgun","first_air_date":"2024-02-27","overview":"…",
             "poster_path":"/p.jpg","backdrop_path":"/b.jpg","number_of_seasons":1,
             "vote_average":8.7,"genres":[{"id":18,"name":"Drama"}]}
            """#)
            let client = TMDBClient(apiKey: "KEY", http: HTTPClient(session: .mock))
            let details = try await client.tvDetails(id: 110492)
            #expect(details.name == "Shōgun")
            #expect(details.numberOfSeasons == 1)
            #expect(details.genres[0].name == "Drama")
        }

        @Test func buildsPosterURL() {
            let url = TMDBClient.imageURL(path: "/abc.jpg", size: "w500")
            #expect(url?.absoluteString == "https://image.tmdb.org/t/p/w500/abc.jpg")
            #expect(TMDBClient.imageURL(path: nil) == nil)
        }
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path Packages/DebridCore --filter TMDBClientTests`
Expected: FAIL — `movieDetails` / `tvDetails` / `imageURL` not defined.

- [ ] **Step 3: Implement details + image helper**

Add to `TMDBClient` (after `searchTV`, before the private `get`):
```swift
    public func movieDetails(id: Int) async throws -> TMDBMovieDetails {
        try await get("movie/\(id)", [])
    }

    public func tvDetails(id: Int) async throws -> TMDBTVDetails {
        try await get("tv/\(id)", [])
    }

    /// Builds a TMDB image URL from a `poster_path`/`backdrop_path` (e.g. "/abc.jpg").
    /// Returns nil when `path` is nil. `size` is a TMDB size token like "w500" or "original".
    public static func imageURL(path: String?, size: String = "w500") -> URL? {
        guard let path else { return nil }
        return URL(string: imageBase + size + path)
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path Packages/DebridCore --filter TMDBClientTests`
Expected: PASS (5 TMDB tests). Full suite → 40 tests green and stable (run twice). No warnings.

- [ ] **Step 5: Commit**

```bash
git add Packages/DebridCore
git commit -m "feat(core): TMDB movie/tv details + image URL helper"
```

---

## Done when

- [ ] `swift test --package-path Packages/DebridCore` green (~40 tests), stable, zero warnings.
- [ ] `DebridCore` exposes: `ParsedRelease`, `FilenameParser.parse(_:)`, `TMDBSearchResult` (+ `displayTitle`/`year`), `TMDBMovieDetails`/`TMDBTVDetails`/`TMDBGenre`, and `TMDBClient` (`searchMovie`, `searchTV`, `movieDetails`, `tvDetails`, static `imageURL`).
- [ ] The TMDB API key is injected (never committed); the build needs no real key.
- [ ] All work committed.

**Setup note (for app-wiring later):** obtain a free TMDB API key (themoviedb.org → Settings → API) and supply it via `Secrets.xcconfig` when the app target is built (Plan 5). Not needed for this plan.

**Next:** Plan 4 — `LibraryBuilder`: combine RD torrents + `FilenameParser` + `TMDBClient` into an organized Movies/Shows library (handling movies, single episodes, and season packs).
