# Real-Debrid Resources — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `DebridCore`'s Real-Debrid resource layer — list the user's torrents, fetch a torrent's files + restricted links, unrestrict a link into a directly-streamable URL, and resolve a playable URL for a torrent's primary video file.

**Architecture:** A `TorrentsClient` value type over the existing `HTTPClient`, authenticated through an injected `AccessTokenProviding` seam (`RealDebridSession` conforms — so the client never touches the Keychain or refresh logic directly, and tests use a stub). Real-Debrid REST resources live under their OWN base constant (`https://api.real-debrid.com/rest/1.0`), distinct from the OAuth base. Pure model helpers encode RD's quirks (the `links` array is ordered by *selected* file; the "primary" file is the largest video). Everything is unit-tested with `MockURLProtocol` + a stub token provider — **no API key required**.

**Tech Stack:** Swift 6.3 (Swift 6 language mode), SPM, async/await, Swift Testing.

**Plan 2 of the Seret roadmap.** The original "Plan 2" (RD resources + metadata) is split: this plan is RD resources; the recognition engine (filename parser → TMDB → organized library) becomes Plan 3.

---

## File Structure

| File | Responsibility |
|---|---|
| `Sources/DebridCore/RealDebrid/RealDebridResourceModels.swift` | `Torrent`, `TorrentFile`, `TorrentInfo` (+ `selectedFilesWithLinks`, `primaryVideoFile`), `UnrestrictedLink` |
| `Sources/DebridCore/RealDebrid/TorrentsClient.swift` | `AccessTokenProviding` protocol (+ `RealDebridSession` conformance) and `TorrentsClient` (list / info / unrestrict / playableURL) |
| `Tests/DebridCoreTests/RealDebridResourceModelsTests.swift` | Decode fixtures + the pure helpers (plain suite, no network) |
| `Tests/DebridCoreTests/TorrentsClientTests.swift` | Client behavior (nested under `MockTests` — uses the network mock) |

> **Note on test placement:** `TorrentsClientTests` uses `MockURLProtocol`, so it MUST be nested under the existing `MockTests` serialized parent (like the other network suites). `RealDebridResourceModelsTests` is pure (no network) and stays a plain top-level `struct`.

---

## Task 1: Real-Debrid resource models + pure helpers

**Files:**
- Create: `Packages/DebridCore/Sources/DebridCore/RealDebrid/RealDebridResourceModels.swift`
- Create: `Packages/DebridCore/Tests/DebridCoreTests/RealDebridResourceModelsTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/DebridCoreTests/RealDebridResourceModelsTests.swift`:
```swift
import Testing
import Foundation
@testable import DebridCore

struct RealDebridResourceModelsTests {
    @Test func decodesTorrentListItem() throws {
        let json = #"""
        {"id":"ABC","filename":"Dune.Part.Two.2024.2160p.mkv","hash":"deadbeef",
         "bytes":25000000000,"host":"real-debrid.com","progress":100,
         "status":"downloaded","added":"2024-03-01T12:00:00.000Z",
         "links":["https://real-debrid.com/d/AAA"],"ended":"2024-03-01T12:05:00.000Z"}
        """#
        let torrent = try JSONDecoder().decode(Torrent.self, from: Data(json.utf8))
        #expect(torrent.id == "ABC")
        #expect(torrent.status == "downloaded")
        #expect(torrent.progress == 100)
        #expect(torrent.links == ["https://real-debrid.com/d/AAA"])
    }

    @Test func decodesTorrentInfoWithFiles() throws {
        let json = #"""
        {"id":"ABC","filename":"Show.S01.1080p","hash":"beef","bytes":3000,
         "progress":100,"status":"downloaded",
         "files":[
           {"id":1,"path":"/Show.S01/sample.mkv","bytes":50,"selected":0},
           {"id":2,"path":"/Show.S01/E01.mkv","bytes":2000,"selected":1},
           {"id":3,"path":"/Show.S01/E02.mkv","bytes":900,"selected":1}],
         "links":["https://real-debrid.com/d/E01","https://real-debrid.com/d/E02"]}
        """#
        let info = try JSONDecoder().decode(TorrentInfo.self, from: Data(json.utf8))
        #expect(info.files.count == 3)
        #expect(info.links.count == 2)
    }

    @Test func decodesUnrestrictedLink() throws {
        let json = #"""
        {"id":"X","filename":"movie.mkv","mimeType":"video/x-matroska",
         "filesize":24000000000,"link":"https://real-debrid.com/d/X",
         "download":"https://srv.download.real-debrid.com/d/X/movie.mkv","streamable":1}
        """#
        let link = try JSONDecoder().decode(UnrestrictedLink.self, from: Data(json.utf8))
        #expect(link.download == "https://srv.download.real-debrid.com/d/X/movie.mkv")
        #expect(link.filename == "movie.mkv")
        #expect(link.mimeType == "video/x-matroska")
    }

    @Test func pairsSelectedFilesWithLinksInOrder() {
        let info = TorrentInfo(
            id: "ABC", filename: "Show.S01", hash: "beef", bytes: 3000,
            progress: 100, status: "downloaded",
            files: [
                TorrentFile(id: 1, path: "/Show/sample.mkv", bytes: 50, selected: 0),
                TorrentFile(id: 2, path: "/Show/E01.mkv", bytes: 2000, selected: 1),
                TorrentFile(id: 3, path: "/Show/E02.mkv", bytes: 900, selected: 1),
            ],
            links: ["https://rd/E01", "https://rd/E02"])
        let pairs = info.selectedFilesWithLinks()
        #expect(pairs.count == 2)
        #expect(pairs[0].file.id == 2)
        #expect(pairs[0].link == "https://rd/E01")
        #expect(pairs[1].file.id == 3)
        #expect(pairs[1].link == "https://rd/E02")
    }

    @Test func primaryVideoFileIsLargestSelectedVideo() {
        let info = TorrentInfo(
            id: "ABC", filename: "Movie", hash: "beef", bytes: 3000,
            progress: 100, status: "downloaded",
            files: [
                TorrentFile(id: 1, path: "/Movie/movie.mkv", bytes: 2000, selected: 1),
                TorrentFile(id: 2, path: "/Movie/extras.mkv", bytes: 2500, selected: 0), // not selected
                TorrentFile(id: 3, path: "/Movie/readme.txt", bytes: 9, selected: 1),    // not video
            ],
            links: ["https://rd/movie", "https://rd/readme"])
        let primary = info.primaryVideoFile()
        #expect(primary?.file.id == 1)
        #expect(primary?.link == "https://rd/movie")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path Packages/DebridCore --filter RealDebridResourceModelsTests`
Expected: FAIL — `Torrent` / `TorrentInfo` / `UnrestrictedLink` not defined.

- [ ] **Step 3: Implement the models**

`Sources/DebridCore/RealDebrid/RealDebridResourceModels.swift`:
```swift
import Foundation

/// A torrent in the user's Real-Debrid library (`GET /torrents` item).
public struct Torrent: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let filename: String
    public let hash: String
    public let bytes: Int
    public let host: String
    public let progress: Double
    public let status: String
    public let added: String
    public let links: [String]
    public let ended: String?

    public init(id: String, filename: String, hash: String, bytes: Int, host: String,
                progress: Double, status: String, added: String, links: [String], ended: String? = nil) {
        self.id = id; self.filename = filename; self.hash = hash; self.bytes = bytes
        self.host = host; self.progress = progress; self.status = status
        self.added = added; self.links = links; self.ended = ended
    }
}

/// A file inside a torrent (`GET /torrents/info/{id}` → `files[]`).
public struct TorrentFile: Decodable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let path: String
    public let bytes: Int
    public let selected: Int   // 1 = selected for download, 0 = skipped

    public init(id: Int, path: String, bytes: Int, selected: Int) {
        self.id = id; self.path = path; self.bytes = bytes; self.selected = selected
    }
}

/// Detailed torrent info (`GET /torrents/info/{id}`).
public struct TorrentInfo: Decodable, Sendable, Equatable {
    public let id: String
    public let filename: String
    public let hash: String
    public let bytes: Int
    public let progress: Double
    public let status: String
    public let files: [TorrentFile]
    public let links: [String]

    public init(id: String, filename: String, hash: String, bytes: Int, progress: Double,
                status: String, files: [TorrentFile], links: [String]) {
        self.id = id; self.filename = filename; self.hash = hash; self.bytes = bytes
        self.progress = progress; self.status = status; self.files = files; self.links = links
    }
}

public extension TorrentInfo {
    /// Real-Debrid returns `links` in the order of the *selected* files. Pairs each
    /// selected file (`selected == 1`) with its restricted link by that order.
    func selectedFilesWithLinks() -> [(file: TorrentFile, link: String)] {
        let selected = files.filter { $0.selected == 1 }
        return Array(zip(selected, links).map { (file: $0, link: $1) })
    }

    /// The largest *selected video* file paired with its restricted link — the thing
    /// you actually want to play. Returns nil if there's no selected video file.
    func primaryVideoFile() -> (file: TorrentFile, link: String)? {
        let videoExtensions: Set<String> = ["mkv", "mp4", "avi", "m4v", "mov", "ts", "wmv"]
        return selectedFilesWithLinks()
            .filter { videoExtensions.contains(($0.file.path as NSString).pathExtension.lowercased()) }
            .max { $0.file.bytes < $1.file.bytes }
    }
}

/// A restricted link resolved into a directly-streamable URL (`POST /unrestrict/link`).
public struct UnrestrictedLink: Decodable, Sendable, Equatable {
    public let download: String      // the direct, streamable URL — hand this to the player
    public let filename: String
    public let filesize: Int
    public let mimeType: String?

    public init(download: String, filename: String, filesize: Int, mimeType: String?) {
        self.download = download; self.filename = filename
        self.filesize = filesize; self.mimeType = mimeType
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path Packages/DebridCore --filter RealDebridResourceModelsTests`
Expected: PASS (5 tests). Full suite still green (`swift test --package-path Packages/DebridCore` → 22 tests).

- [ ] **Step 5: Commit**

```bash
git add Packages/DebridCore
git commit -m "feat(core): Real-Debrid resource models + selected-file/primary-video helpers"
```

---

## Task 2: AccessTokenProviding seam + TorrentsClient (list + info)

**Files:**
- Create: `Packages/DebridCore/Sources/DebridCore/RealDebrid/TorrentsClient.swift`
- Create: `Packages/DebridCore/Tests/DebridCoreTests/TorrentsClientTests.swift`

- [ ] **Step 1: Write the failing test** (nested under `MockTests` — it uses the network mock)

`Tests/DebridCoreTests/TorrentsClientTests.swift`:
```swift
import Testing
import Foundation
@testable import DebridCore

extension MockTests {
    @Suite struct TorrentsClientTests {
        init() { MockURLProtocol.handler = nil }

        struct StubTokens: AccessTokenProviding {
            func validAccessToken() async throws -> String { "TESTTOKEN" }
        }

        @Test func listsTorrents() async throws {
            MockURLProtocol.stub(status: 200, json: #"""
            [{"id":"A","filename":"Movie.2024.mkv","hash":"h","bytes":10,"host":"rd",
              "progress":100,"status":"downloaded","added":"2024-01-01T00:00:00.000Z",
              "links":["https://rd/A"]}]
            """#)
            let client = TorrentsClient(http: HTTPClient(session: .mock), tokens: StubTokens())
            let torrents = try await client.torrents()
            #expect(torrents.count == 1)
            #expect(torrents[0].id == "A")
        }

        @Test func fetchesTorrentInfo() async throws {
            MockURLProtocol.stub(status: 200, json: #"""
            {"id":"A","filename":"Movie","hash":"h","bytes":10,"progress":100,
             "status":"downloaded",
             "files":[{"id":1,"path":"/Movie/movie.mkv","bytes":10,"selected":1}],
             "links":["https://rd/A"]}
            """#)
            let client = TorrentsClient(http: HTTPClient(session: .mock), tokens: StubTokens())
            let info = try await client.info(id: "A")
            #expect(info.files.count == 1)
            #expect(info.links == ["https://rd/A"])
        }

        @Test func realDebridSessionConformsToAccessTokenProviding() async throws {
            // Compile-time + behavior check that RealDebridSession is usable as the token source.
            let store = InMemoryTokenStore()
            let t0 = Date(timeIntervalSince1970: 1_000_000)
            try store.save(StoredCredentials(
                token: RDToken(accessToken: "LIVE", refreshToken: "R", expiresIn: 3600, tokenType: "Bearer"),
                deviceCredentials: RDDeviceCredentials(clientID: "C", clientSecret: "S"),
                obtainedAt: t0))
            let session = RealDebridSession(store: store, now: { t0.addingTimeInterval(60) })
            let provider: AccessTokenProviding = session
            #expect(try await provider.validAccessToken() == "LIVE")
        }
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path Packages/DebridCore --filter TorrentsClientTests`
Expected: FAIL — `TorrentsClient` / `AccessTokenProviding` not defined.

- [ ] **Step 3: Implement the seam + client**

`Sources/DebridCore/RealDebrid/TorrentsClient.swift`:
```swift
import Foundation

/// Supplies a currently-valid Real-Debrid access token. `RealDebridSession` conforms;
/// tests use a stub. Keeps `TorrentsClient` decoupled from Keychain/refresh details.
public protocol AccessTokenProviding: Sendable {
    func validAccessToken() async throws -> String
}

extension RealDebridSession: AccessTokenProviding {}

/// Reads the user's Real-Debrid library and resolves playable URLs.
public struct TorrentsClient: Sendable {
    /// Real-Debrid REST resource base — distinct from the OAuth base in `RealDebridAuthClient`.
    public static let base = URL(string: "https://api.real-debrid.com/rest/1.0")!

    private let http: HTTPClient
    private let tokens: AccessTokenProviding

    public init(http: HTTPClient = HTTPClient(), tokens: AccessTokenProviding) {
        self.http = http
        self.tokens = tokens
    }

    private func authHeaders() async throws -> [String: String] {
        ["Authorization": "Bearer \(try await tokens.validAccessToken())"]
    }

    /// One page of the user's torrents (RD paginates; default page size 100).
    public func torrents(page: Int = 1, limit: Int = 100) async throws -> [Torrent] {
        var comps = URLComponents(url: Self.base.appending(path: "torrents"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "page", value: String(page)),
            .init(name: "limit", value: String(limit)),
        ]
        return try await http.get(comps.url!, headers: try await authHeaders())
    }

    /// Files + restricted links for a single torrent.
    public func info(id: String) async throws -> TorrentInfo {
        try await http.get(Self.base.appending(path: "torrents/info/\(id)"),
                           headers: try await authHeaders())
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path Packages/DebridCore --filter TorrentsClientTests`
Expected: PASS (3 tests). Full suite → 25 tests green.

- [ ] **Step 5: Commit**

```bash
git add Packages/DebridCore
git commit -m "feat(core): TorrentsClient list/info + AccessTokenProviding seam"
```

---

## Task 3: Unrestrict a link + resolve a playable URL

**Files:**
- Modify: `Packages/DebridCore/Sources/DebridCore/RealDebrid/TorrentsClient.swift`
- Modify: `Packages/DebridCore/Tests/DebridCoreTests/TorrentsClientTests.swift`

- [ ] **Step 1: Write the failing tests** (add inside the existing `TorrentsClientTests` struct)

Add these two tests after `fetchesTorrentInfo`:
```swift
        @Test func unrestrictsALink() async throws {
            MockURLProtocol.stub(status: 200, json: #"""
            {"id":"X","filename":"movie.mkv","mimeType":"video/x-matroska","filesize":10,
             "link":"https://real-debrid.com/d/X",
             "download":"https://srv.download.real-debrid.com/d/X/movie.mkv","streamable":1}
            """#)
            let client = TorrentsClient(http: HTTPClient(session: .mock), tokens: StubTokens())
            let link = try await client.unrestrict(link: "https://real-debrid.com/d/X")
            #expect(link.download == "https://srv.download.real-debrid.com/d/X/movie.mkv")
        }

        @Test func playableURLPicksPrimaryVideoThenUnrestricts() async throws {
            let info = TorrentInfo(
                id: "A", filename: "Movie", hash: "h", bytes: 10, progress: 100, status: "downloaded",
                files: [TorrentFile(id: 1, path: "/Movie/movie.mkv", bytes: 2000, selected: 1)],
                links: ["https://real-debrid.com/d/X"])
            MockURLProtocol.stub(status: 200, json: #"""
            {"id":"X","filename":"movie.mkv","mimeType":"video/x-matroska","filesize":2000,
             "link":"https://real-debrid.com/d/X",
             "download":"https://srv.download.real-debrid.com/d/X/movie.mkv","streamable":1}
            """#)
            let client = TorrentsClient(http: HTTPClient(session: .mock), tokens: StubTokens())
            let link = try await client.playableURL(for: info)
            #expect(link?.download == "https://srv.download.real-debrid.com/d/X/movie.mkv")
        }

        @Test func playableURLIsNilWhenNoVideoFile() async throws {
            let info = TorrentInfo(
                id: "A", filename: "Pack", hash: "h", bytes: 10, progress: 100, status: "downloaded",
                files: [TorrentFile(id: 1, path: "/Pack/readme.txt", bytes: 9, selected: 1)],
                links: ["https://real-debrid.com/d/X"])
            let client = TorrentsClient(http: HTTPClient(session: .mock), tokens: StubTokens())
            let link = try await client.playableURL(for: info)
            #expect(link == nil)
        }
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path Packages/DebridCore --filter TorrentsClientTests`
Expected: FAIL — `unrestrict` / `playableURL` not defined.

- [ ] **Step 3: Implement unrestrict + playableURL**

Add these methods to `TorrentsClient` (after `info(id:)`):
```swift
    /// Turns an RD restricted link into a directly-streamable URL. Resolve this lazily,
    /// right before playback — unrestricted URLs expire.
    public func unrestrict(link: String) async throws -> UnrestrictedLink {
        try await http.post(Self.base.appending(path: "unrestrict/link"),
                            form: ["link": link],
                            headers: try await authHeaders())
    }

    /// Convenience: pick the torrent's primary video file and unrestrict its link.
    /// Returns nil if the torrent has no selected video file.
    public func playableURL(for info: TorrentInfo) async throws -> UnrestrictedLink? {
        guard let primary = info.primaryVideoFile() else { return nil }
        return try await unrestrict(link: primary.link)
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path Packages/DebridCore --filter TorrentsClientTests`
Expected: PASS. Full suite → 28 tests green. Run the full suite twice to confirm stability (the mock-using suites are serialized):
Run: `swift test --package-path Packages/DebridCore`
Expected: `28 tests` pass, stable.

- [ ] **Step 5: Commit**

```bash
git add Packages/DebridCore
git commit -m "feat(core): unrestrict links + resolve playable URL for a torrent"
```

---

## Done when

- [ ] `swift test --package-path Packages/DebridCore` is green (~28 tests) and stable across runs.
- [ ] `DebridCore` exposes: `Torrent`, `TorrentInfo` (+ `selectedFilesWithLinks`, `primaryVideoFile`), `UnrestrictedLink`, `AccessTokenProviding` (with `RealDebridSession` conforming), and `TorrentsClient` (`torrents`, `info`, `unrestrict`, `playableURL`).
- [ ] RD resources use their own `/rest/1.0` base constant (separate from the OAuth base) — closes the Plan-1 review follow-up.
- [ ] No tokens or URLs logged.
- [ ] All work committed.

**Optional integration check (manual, needs the live account):** with a real `RealDebridSession`, `TorrentsClient(tokens: session).torrents()` should list the user's actual RD library. Not part of the automated suite.

**Next:** Plan 3 — the recognition engine (`FilenameParser` → TMDB → organized Movies/Shows library).
