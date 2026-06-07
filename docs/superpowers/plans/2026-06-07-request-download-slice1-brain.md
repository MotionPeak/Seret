# Request Download — Slice 1 (Brain) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the DebridCore engine that lets the app fetch a torrent for an uncached title, add it to Real-Debrid for download (without the instant-only delete), persist the request, and monitor its progress to completion — all unit-tested with mocks. UI is a later slice.

**Architecture:** Reuses the Stage 2 `StreamSource`/Comet path (flip `cachedOnly`) and the existing `[CachedStream]` ranking. Adds: an uncached-aware `StreamSource` method, a `TorrentsClient.addForDownload` (add+selectFiles, keep the torrent), a `DownloadRequesting` seam, a persisted `DownloadsStore` (SwiftData `@ModelActor`, mirrors `WatchProgressStore`), and a `DownloadMonitor` that polls RD and maps status→progress. `AppSession` composes them.

**Tech Stack:** Swift 6 / strict concurrency, SwiftData, Swift Testing. DebridCore tested via `swift test` (no simulator). Network mocked with the existing `MockURLProtocol`/`MockTests`; SwiftData tests nest under `SwiftDataSuite`.

**Branch:** `feat/stage2-search-add`. Stage only the paths each task names — never `git add -A` (the owner edits other files in parallel; there are unrelated uncommitted changes).

**Spec:** `docs/superpowers/specs/2026-06-07-request-download-uncached-design.md`

---

## File Structure

**DebridCore (brain):**
- Modify `Packages/DebridCore/Sources/DebridCore/Search/StreamSource.swift` — add the uncached-aware requirement (extension default + Comet override).
- Modify `Packages/DebridCore/Sources/DebridCore/Search/CometStreamSource.swift` — honor `includeUncached` in the config; refactor `streams(for:)` to delegate.
- Modify `Packages/DebridCore/Sources/DebridCore/RealDebrid/TorrentsClient.swift` — add `addForDownload(magnetHash:)`.
- Create `Packages/DebridCore/Sources/DebridCore/Downloads/DownloadRequesting.swift` — the seam + `RealDebridDownloadService`.
- Create `Packages/DebridCore/Sources/DebridCore/Downloads/DownloadStatus.swift` — pure `TorrentInfo`→status mapper.
- Create `Packages/DebridCore/Sources/DebridCore/Downloads/DownloadRequest.swift` — SwiftData `@Model` + `DownloadRequestData` DTO.
- Create `Packages/DebridCore/Sources/DebridCore/Downloads/DownloadsStore.swift` — `@ModelActor` persistence.
- Create `Packages/DebridCore/Sources/DebridCore/Downloads/DownloadMonitor.swift` — poll-once orchestrator + `DownloadInfoProviding` seam.
- Tests under `Packages/DebridCore/Tests/DebridCoreTests/`.

**DebridUI (composition only):**
- Modify `Shared/DebridUI/Sources/DebridUI/Shell/AppSession.swift` — compose the new pieces (private refs for Slice 2).

---

## Task 1: Research spike — confirm Comet returns uncached results (GATE, owner-assisted)

This validates the make-or-break unknown before Slice 2 (UI). It needs a **real RD token** (Comet returns `[❌] realdebrid: Invalid API key` for an empty token — verified), so it is **owner-assisted**. Tasks 2–7 are mock-tested and may be built before this resolves, but **do not start Slice 2 until this passes.**

- [ ] **Step 1: Pick a title with no cached version**

Use a title the owner knows is NOT instantly cached (e.g. "The Happy Film", a niche documentary). Get its IMDB id (e.g. from TMDB → external ids). For the probe below use that `ttXXXXXXX`.

- [ ] **Step 2: Compare cached-only vs all (owner runs this; token never printed/committed)**

Ask the owner to run this in a terminal, substituting their RD token for `$RDTOKEN` (do NOT echo or commit the token):

```bash
RDTOKEN='<paste RD token>'
b64() { python3 -c "import base64,sys;print(base64.b64encode(sys.argv[1].encode()).decode())" "$1"; }
IMDB='tt_REPLACE_ME'
for mode in true false; do
  cfg="{\"debridService\":\"realdebrid\",\"debridApiKey\":\"$RDTOKEN\",\"cachedOnly\":$mode,\"resultFormat\":[\"all\"]}"
  echo "=== cachedOnly:$mode ==="
  curl -s --max-time 30 "https://comet.elfhosted.com/$(b64 "$cfg")/stream/movie/$IMDB.json" \
    | python3 -c "import sys,json;d=json.load(sys.stdin);s=d.get('streams',[]);print('count',len(s));[print(repr(x.get('name'))[:80],'|',(''.join((x.get('description') or '').splitlines()[:1]))[:90]) for x in s[:8]]"
done
```

- [ ] **Step 3: Evaluate the gate**

PASS if `cachedOnly:false` returns **more streams than `cachedOnly:true`** for this title (i.e. uncached torrents are surfaced) — ideally `cachedOnly:true` returns 0 and `false` returns several. Note how cached vs uncached is **labeled** in the `name` (e.g. a "⚡"/"[RD+]" marker vs a download marker) — record it; Slice 2 may use it to label "instant vs will download," but the core flow does not depend on it.

FAIL if `cachedOnly:false` returns nothing extra → Comet can't surface uncached; STOP and revisit the torrent source (different indexer) before Slice 2.

- [ ] **Step 4: Record the outcome**

Append a short note (counts + labeling observed + PASS/FAIL) to the spec file under a new "## Spike result (2026-06-07)" heading and commit:

```bash
git add docs/superpowers/specs/2026-06-07-request-download-uncached-design.md
git commit -m "docs: record Comet uncached spike result"
```

---

## Task 2: Uncached-aware `StreamSource` discovery

**Files:**
- Modify: `Packages/DebridCore/Sources/DebridCore/Search/StreamSource.swift`
- Modify: `Packages/DebridCore/Sources/DebridCore/Search/CometStreamSource.swift`
- Test: `Packages/DebridCore/Tests/DebridCoreTests/CometUncachedTests.swift` (create)

- [ ] **Step 1: Write the failing test**

Create `Packages/DebridCore/Tests/DebridCoreTests/CometUncachedTests.swift`. It asserts that `includeUncached: true` sends `cachedOnly:false` in the base64 config segment of the request URL, and `false` (the default) sends `cachedOnly:true`. The handler decodes the path's first segment.

```swift
import Testing
import Foundation
@testable import DebridCore

extension MockTests {
    @Suite struct CometUncachedTests {
        init() { MockURLProtocol.handler = nil }

        struct StubTokens: AccessTokenProviding {
            func validAccessToken() async throws -> String { "TESTTOKEN" }
        }

        /// Decodes the `cachedOnly` value from the base64 config segment of a Comet URL.
        private static func cachedOnlyFlag(in url: URL) -> Bool? {
            // Path: /<base64cfg>/stream/movie/<id>.json — first non-empty segment is the config.
            guard let seg = url.pathComponents.first(where: { $0 != "/" && !$0.isEmpty }),
                  let data = Data(base64Encoded: seg),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }
            return json["cachedOnly"] as? Bool
        }

        private func source() -> CometStreamSource {
            CometStreamSource(http: HTTPClient(session: .mock), tokens: StubTokens())
        }
        private func query() -> StreamQuery {
            StreamQuery(imdbID: "tt0133093", kind: .movie, originalLanguage: "en")
        }

        @Test func includeUncachedSendsCachedOnlyFalse() async throws {
            let box = FlagBox()
            MockURLProtocol.handler = { req in
                box.flag = Self.cachedOnlyFlag(in: req.url!)
                return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                        Data(#"{"streams":[]}"#.utf8))
            }
            _ = try await source().streams(for: query(), includeUncached: true)
            #expect(box.flag == false)   // cachedOnly:false → uncached included
        }

        @Test func defaultStaysCachedOnly() async throws {
            let box = FlagBox()
            MockURLProtocol.handler = { req in
                box.flag = Self.cachedOnlyFlag(in: req.url!)
                return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                        Data(#"{"streams":[]}"#.utf8))
            }
            _ = try await source().streams(for: query())   // existing cached path
            #expect(box.flag == true)
        }
    }
}

private final class FlagBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _flag: Bool?
    var flag: Bool? {
        get { lock.lock(); defer { lock.unlock() }; return _flag }
        set { lock.lock(); _flag = newValue; lock.unlock() }
    }
}
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `cd Packages/DebridCore && swift test --filter CometUncachedTests`
Expected: FAIL — `streams(for:includeUncached:)` doesn't exist yet.

- [ ] **Step 3: Add the protocol requirement + default**

In `Packages/DebridCore/Sources/DebridCore/Search/StreamSource.swift`, replace the file body with:

```swift
/// A source of torrents for a title (e.g. the Comet Stremio addon).
public protocol StreamSource: Sendable {
    /// Instantly-cached streams for the query, unranked (caller ranks).
    func streams(for query: StreamQuery) async throws -> [CachedStream]
}

public extension StreamSource {
    /// Candidates for the query. When `includeUncached` is true, sources that support it return
    /// uncached torrents too (for "request download"); the default ignores the flag for
    /// cached-only sources.
    func streams(for query: StreamQuery, includeUncached: Bool) async throws -> [CachedStream] {
        try await streams(for: query)
    }
}
```

- [ ] **Step 4: Make Comet honor the flag**

In `Packages/DebridCore/Sources/DebridCore/Search/CometStreamSource.swift`, replace the existing `streams(for:)` method with a delegating pair (concrete `streams(for:includeUncached:)` overrides the extension default):

```swift
    public func streams(for query: StreamQuery) async throws -> [CachedStream] {
        try await streams(for: query, includeUncached: false)
    }

    public func streams(for query: StreamQuery, includeUncached: Bool) async throws -> [CachedStream] {
        let token = try await tokens.validAccessToken()
        let cachedOnly = includeUncached ? "false" : "true"
        let config = #"{"debridService":"realdebrid","debridApiKey":""# + token
            + #"","cachedOnly":"# + cachedOnly + #","resultFormat":["all"]}"#
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
        let mapped = response.streams.compactMap { map($0) }
        return Self.validate(mapped, against: query)
    }
```

(The `map`, `validate`, and DTO code below it stay unchanged.)

- [ ] **Step 5: Run the test, verify it passes**

Run: `cd Packages/DebridCore && swift test --filter CometUncachedTests`
Expected: PASS (2 tests).

- [ ] **Step 6: Full suite (no regressions in the existing cached path)**

Run: `cd Packages/DebridCore && swift test`
Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git add Packages/DebridCore/Sources/DebridCore/Search/StreamSource.swift \
        Packages/DebridCore/Sources/DebridCore/Search/CometStreamSource.swift \
        Packages/DebridCore/Tests/DebridCoreTests/CometUncachedTests.swift
git commit -m "feat(core): StreamSource can fetch uncached candidates (cachedOnly:false)"
```

---

## Task 3: `TorrentsClient.addForDownload` + `DownloadRequesting` seam

**Files:**
- Modify: `Packages/DebridCore/Sources/DebridCore/RealDebrid/TorrentsClient.swift`
- Create: `Packages/DebridCore/Sources/DebridCore/Downloads/DownloadRequesting.swift`
- Test: `Packages/DebridCore/Tests/DebridCoreTests/AddForDownloadTests.swift` (create)

`addForDownload` mirrors the first half of the existing private `selectAndAwaitDownloaded`: addMagnet → wait for file listing → `selectFiles(videoIDs|all)` → return current info. Unlike `add`, it does **not** wait for `downloaded` and does **not** delete the torrent on non-instant. It throws `RDAddError.failed` on a terminal status seen during listing.

- [ ] **Step 1: Write the failing test**

Create `Packages/DebridCore/Tests/DebridCoreTests/AddForDownloadTests.swift`:

```swift
import Testing
import Foundation
@testable import DebridCore

extension MockTests {
    @Suite struct AddForDownloadTests {
        init() { MockURLProtocol.handler = nil }

        struct StubTokens: AccessTokenProviding {
            func validAccessToken() async throws -> String { "T" }
        }
        private func client() -> TorrentsClient {
            TorrentsClient(http: HTTPClient(session: .mock), tokens: StubTokens())
        }
        private static func resp(_ req: URLRequest, _ status: Int, _ json: String) -> (HTTPURLResponse, Data) {
            (HTTPURLResponse(url: req.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
        }
        // A torrent that is downloading (not cached): files listed, status "downloading", progress 12.
        private static func infoJSON(_ status: String, progress: Int) -> String {
            #"{"id":"TID","filename":"x","hash":"h","bytes":1,"progress":\#(progress),"status":"\#(status)","files":[{"id":1,"path":"/movie.mkv","bytes":1,"selected":0}],"links":[]}"#
        }

        @Test func addsSelectsAndReturnsWithoutWaitingForDownloaded() async throws {
            let selected = SelectFlag()
            MockURLProtocol.handler = { req in
                let u = req.url!.absoluteString
                if u.contains("addMagnet") { return Self.resp(req, 201, #"{"id":"TID","uri":"u"}"#) }
                if u.contains("selectFiles") { selected.value = true; return Self.resp(req, 204, "") }
                if u.contains("/torrents/info/") { return Self.resp(req, 200, Self.infoJSON("downloading", progress: 12)) }
                return Self.resp(req, 200, "{}")
            }
            let info = try await client().addForDownload(magnetHash: "abc", pollInterval: .zero, sleep: { _ in })
            #expect(info.id == "TID")
            #expect(info.status == "downloading")   // returned mid-download, NOT awaited to "downloaded"
            #expect(selected.value == true)         // files were selected
        }

        @Test func terminalStatusDuringListingThrows() async throws {
            MockURLProtocol.handler = { req in
                let u = req.url!.absoluteString
                if u.contains("addMagnet") { return Self.resp(req, 201, #"{"id":"TID","uri":"u"}"#) }
                if u.contains("/torrents/info/") {
                    return Self.resp(req, 200, #"{"id":"TID","filename":"x","hash":"h","bytes":1,"progress":0,"status":"dead","files":[],"links":[]}"#)
                }
                return Self.resp(req, 200, "{}")
            }
            await #expect(throws: RDAddError.self) {
                _ = try await client().addForDownload(magnetHash: "abc", pollInterval: .zero, sleep: { _ in })
            }
        }
    }
}

private final class SelectFlag: @unchecked Sendable {
    private let lock = NSLock(); private var _v = false
    var value: Bool { get { lock.lock(); defer { lock.unlock() }; return _v } set { lock.lock(); _v = newValue; lock.unlock() } }
}
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `cd Packages/DebridCore && swift test --filter AddForDownloadTests`
Expected: FAIL — `addForDownload` doesn't exist.

- [ ] **Step 3: Implement `addForDownload`**

In `Packages/DebridCore/Sources/DebridCore/RealDebrid/TorrentsClient.swift`, add after the `add(magnetHash:...)` method:

```swift
    /// Add a magnet and select its video files for download, then return immediately — does NOT
    /// wait for `downloaded` and does NOT delete on non-instant (that's the whole point: we want
    /// RD to download an uncached torrent in the background). Throws `RDAddError.failed` on a
    /// terminal status seen while waiting for the file listing. The caller monitors progress.
    public func addForDownload(magnetHash: String,
                               maxListAttempts: Int = 10,
                               pollInterval: Duration = .seconds(1),
                               sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) async throws -> TorrentInfo {
        let added = try await addMagnet(magnet: "magnet:?xt=urn:btih:\(magnetHash)")
        let id = added.id
        var info = try await self.info(id: id)
        var attempts = 0
        while info.files.isEmpty && info.status != "waiting_files_selection" && attempts < maxListAttempts {
            if Self.errorStatuses.contains(info.status) { throw RDAddError.failed(status: info.status, torrentID: id) }
            try await sleep(pollInterval)
            info = try await self.info(id: id)
            attempts += 1
        }
        if Self.errorStatuses.contains(info.status) { throw RDAddError.failed(status: info.status, torrentID: id) }
        let videoIDs = info.videoFileIDs()
        let filesParam = videoIDs.isEmpty ? "all" : videoIDs.map(String.init).joined(separator: ",")
        try await selectFiles(torrentID: id, files: filesParam)
        return try await self.info(id: id)
    }
```

- [ ] **Step 4: Run the test, verify it passes**

Run: `cd Packages/DebridCore && swift test --filter AddForDownloadTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Add the `DownloadRequesting` seam**

Create `Packages/DebridCore/Sources/DebridCore/Downloads/DownloadRequesting.swift`:

```swift
import Foundation

/// Starts a Real-Debrid download for a torrent (by infohash) and returns its initial info.
/// Unlike the instant-only add, this keeps the torrent so RD downloads it in the background.
public protocol DownloadRequesting: Sendable {
    func startDownload(infoHash: String) async throws -> TorrentInfo
}

public struct RealDebridDownloadService: DownloadRequesting {
    private let torrents: TorrentsClient
    public init(torrents: TorrentsClient) { self.torrents = torrents }
    public func startDownload(infoHash: String) async throws -> TorrentInfo {
        try await torrents.addForDownload(magnetHash: infoHash)
    }
}
```

- [ ] **Step 6: Build (no test needed for the trivial wrapper)**

Run: `cd Packages/DebridCore && swift build 2>&1 | grep -i warning; echo "exit ${PIPESTATUS[0]}"`
Expected: builds, no warnings.

- [ ] **Step 7: Commit**

```bash
git add Packages/DebridCore/Sources/DebridCore/RealDebrid/TorrentsClient.swift \
        Packages/DebridCore/Sources/DebridCore/Downloads/DownloadRequesting.swift \
        Packages/DebridCore/Tests/DebridCoreTests/AddForDownloadTests.swift
git commit -m "feat(core): addForDownload keeps an uncached torrent + DownloadRequesting seam"
```

---

## Task 4: `DownloadStatus` pure mapper

**Files:**
- Create: `Packages/DebridCore/Sources/DebridCore/Downloads/DownloadStatus.swift`
- Test: `Packages/DebridCore/Tests/DebridCoreTests/DownloadStatusTests.swift` (create)

- [ ] **Step 1: Write the failing test**

Create `Packages/DebridCore/Tests/DebridCoreTests/DownloadStatusTests.swift`:

```swift
import Testing
import Foundation
@testable import DebridCore

@Suite struct DownloadStatusTests {
    private func info(_ status: String, _ progress: Double) -> TorrentInfo {
        TorrentInfo(id: "T", filename: "f", hash: "h", bytes: 1, progress: progress,
                    status: status, files: [], links: [], added: nil)
    }

    @Test func downloadedIsReadyAtFull() {
        let s = DownloadStatus(from: info("downloaded", 100), tmdbID: 5)
        #expect(s.phase == .ready)
        #expect(s.fraction == 1.0)
        #expect(s.tmdbID == 5)
    }
    @Test func downloadingCarriesFraction() {
        let s = DownloadStatus(from: info("downloading", 42), tmdbID: 5)
        #expect(s.phase == .downloading)
        #expect(abs(s.fraction - 0.42) < 0.0001)
    }
    @Test func queuedStates() {
        #expect(DownloadStatus(from: info("queued", 0), tmdbID: 1).phase == .queued)
        #expect(DownloadStatus(from: info("magnet_conversion", 0), tmdbID: 1).phase == .queued)
    }
    @Test func terminalIsFailed() {
        for st in ["dead", "virus", "error", "magnet_error"] {
            #expect(DownloadStatus(from: info(st, 0), tmdbID: 1).phase == .failed(st))
        }
    }
}
```

NOTE: verify the real `TorrentInfo` initializer signature/labels before running (read `RealDebridResourceModels.swift`); adjust the `info(...)` helper to match the actual public memberwise init (it has a public init per the codebase convention). Do not invent fields.

- [ ] **Step 2: Run the test, verify it fails**

Run: `cd Packages/DebridCore && swift test --filter DownloadStatusTests`
Expected: FAIL — no `DownloadStatus`.

- [ ] **Step 3: Implement**

Create `Packages/DebridCore/Sources/DebridCore/Downloads/DownloadStatus.swift`:

```swift
import Foundation

/// A Sendable snapshot of where a requested download is, derived purely from an RD `TorrentInfo`.
public struct DownloadStatus: Sendable, Equatable, Identifiable {
    public enum Phase: Sendable, Equatable {
        case queued, downloading, ready, failed(String)
    }
    public let torrentID: String
    public let tmdbID: Int
    public let phase: Phase
    public let fraction: Double   // 0...1

    public var id: String { torrentID }

    /// RD statuses that mean the download will never finish.
    static let terminalStatuses: Set<String> = ["error", "magnet_error", "dead", "virus"]
    /// RD statuses before bytes start flowing.
    static let queuedStatuses: Set<String> = ["queued", "magnet_conversion", "waiting_files_selection"]

    public init(from info: TorrentInfo, tmdbID: Int) {
        self.torrentID = info.id
        self.tmdbID = tmdbID
        self.fraction = max(0, min(1, info.progress / 100))
        if info.status == "downloaded" {
            self.phase = .ready
        } else if Self.terminalStatuses.contains(info.status) {
            self.phase = .failed(info.status)
        } else if Self.queuedStatuses.contains(info.status) {
            self.phase = .queued
        } else {
            self.phase = .downloading
        }
    }

    public init(torrentID: String, tmdbID: Int, phase: Phase, fraction: Double) {
        self.torrentID = torrentID; self.tmdbID = tmdbID; self.phase = phase; self.fraction = fraction
    }
}
```

- [ ] **Step 4: Run the test, verify it passes**

Run: `cd Packages/DebridCore && swift test --filter DownloadStatusTests`
Expected: PASS (4 tests). Fix the `ready` fraction case: `downloaded` sets `.ready` and fraction is `progress/100` (100→1.0), consistent with the test.

- [ ] **Step 5: Commit**

```bash
git add Packages/DebridCore/Sources/DebridCore/Downloads/DownloadStatus.swift \
        Packages/DebridCore/Tests/DebridCoreTests/DownloadStatusTests.swift
git commit -m "feat(core): DownloadStatus maps TorrentInfo to a progress phase"
```

---

## Task 5: `DownloadRequest` model + `DownloadsStore` (SwiftData)

**Files:**
- Create: `Packages/DebridCore/Sources/DebridCore/Downloads/DownloadRequest.swift`
- Create: `Packages/DebridCore/Sources/DebridCore/Downloads/DownloadsStore.swift`
- Test: `Packages/DebridCore/Tests/DebridCoreTests/DownloadsStoreTests.swift` (create)

Mirrors `WatchProgress`/`WatchProgressStore` exactly: a CloudKit-ready `@Model` (all properties defaulted, no unique constraints), a `Sendable` DTO returned across the actor boundary, and a `@ModelActor` store. **Tests nest under the `SwiftDataSuite` serialized parent** (per CLAUDE.md — two concurrent in-memory containers SIGSEGV the runner).

- [ ] **Step 1: Write the failing test**

Create `Packages/DebridCore/Tests/DebridCoreTests/DownloadsStoreTests.swift`:

```swift
import Testing
import Foundation
import SwiftData
@testable import DebridCore

extension SwiftDataSuite {
    @Suite struct DownloadsStoreTests {
        private func store() throws -> DownloadsStore {
            let c = try ModelContainer(for: DownloadRequest.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            return DownloadsStore(modelContainer: c)
        }
        private func req(_ torrentID: String, tmdb: Int) -> DownloadRequestData {
            DownloadRequestData(torrentID: torrentID, tmdbID: tmdb, infoHash: "h\(torrentID)",
                                kind: .movie, title: "T\(torrentID)",
                                requestedAt: Date(timeIntervalSince1970: 0))
        }

        @Test func upsertAllAndDelete() async throws {
            let s = try store()
            try await s.upsert(req("A", tmdb: 1))
            try await s.upsert(req("B", tmdb: 2))
            #expect(try await s.all().count == 2)
            try await s.delete(torrentID: "A")
            let rest = try await s.all()
            #expect(rest.map(\.torrentID) == ["B"])
        }

        @Test func upsertReplacesSameTorrent() async throws {
            let s = try store()
            try await s.upsert(req("A", tmdb: 1))
            try await s.upsert(req("A", tmdb: 1))   // same torrentID
            #expect(try await s.all().count == 1)   // deduped, not duplicated
        }

        @Test func findByTMDB() async throws {
            let s = try store()
            try await s.upsert(req("A", tmdb: 7))
            #expect(try await s.find(tmdbID: 7)?.torrentID == "A")
            #expect(try await s.find(tmdbID: 99) == nil)
        }
    }
}
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `cd Packages/DebridCore && swift test --filter DownloadsStoreTests`
Expected: FAIL — no `DownloadRequest`/`DownloadsStore`.

- [ ] **Step 3: Implement the model + DTO**

Create `Packages/DebridCore/Sources/DebridCore/Downloads/DownloadRequest.swift`:

```swift
import Foundation
import SwiftData

/// A title the user asked RD to download. CloudKit-ready (all defaulted, no unique constraint).
/// `torrentID` is the dedupe key (enforced in `DownloadsStore`, not by SwiftData).
@Model
public final class DownloadRequest {
    public var torrentID: String = ""
    public var tmdbID: Int = 0
    public var infoHash: String = ""
    public var kindRaw: String = "movie"   // MediaKind.rawValue
    public var title: String = ""
    public var requestedAt: Date = Date(timeIntervalSince1970: 0)

    public init(torrentID: String = "", tmdbID: Int = 0, infoHash: String = "",
                kindRaw: String = "movie", title: String = "",
                requestedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.torrentID = torrentID; self.tmdbID = tmdbID; self.infoHash = infoHash
        self.kindRaw = kindRaw; self.title = title; self.requestedAt = requestedAt
    }
}

/// A `Sendable` snapshot of a `DownloadRequest` — what the store hands back across the actor boundary.
public struct DownloadRequestData: Sendable, Equatable, Identifiable {
    public let torrentID: String
    public let tmdbID: Int
    public let infoHash: String
    public let kind: MediaKind
    public let title: String
    public let requestedAt: Date

    public var id: String { torrentID }

    public init(torrentID: String, tmdbID: Int, infoHash: String, kind: MediaKind,
                title: String, requestedAt: Date) {
        self.torrentID = torrentID; self.tmdbID = tmdbID; self.infoHash = infoHash
        self.kind = kind; self.title = title; self.requestedAt = requestedAt
    }

    init(_ m: DownloadRequest) {
        self.init(torrentID: m.torrentID, tmdbID: m.tmdbID, infoHash: m.infoHash,
                  kind: MediaKind(rawValue: m.kindRaw) ?? .movie, title: m.title,
                  requestedAt: m.requestedAt)
    }
}
```

- [ ] **Step 4: Implement the store**

Create `Packages/DebridCore/Sources/DebridCore/Downloads/DownloadsStore.swift`:

```swift
import Foundation
import SwiftData

/// SwiftData-backed registry of in-progress download requests. `@ModelActor` isolates its
/// `ModelContext`, so it is safe from any task. Returns `Sendable` `DownloadRequestData` values.
@ModelActor
public actor DownloadsStore {
    /// Insert-or-update the row for `data.torrentID` (CloudKit forbids a unique constraint, so
    /// we dedupe here, mirroring `WatchProgressStore`).
    public func upsert(_ data: DownloadRequestData) throws {
        let row = try fetchOne(torrentID: data.torrentID) ?? {
            let r = DownloadRequest(); modelContext.insert(r); return r
        }()
        row.torrentID = data.torrentID
        row.tmdbID = data.tmdbID
        row.infoHash = data.infoHash
        row.kindRaw = data.kind.rawValue
        row.title = data.title
        row.requestedAt = data.requestedAt
        try modelContext.save()
    }

    public func all() throws -> [DownloadRequestData] {
        try modelContext.fetch(FetchDescriptor<DownloadRequest>(
            sortBy: [SortDescriptor(\.requestedAt, order: .reverse)])).map(DownloadRequestData.init)
    }

    public func find(tmdbID: Int) throws -> DownloadRequestData? {
        var d = FetchDescriptor<DownloadRequest>(predicate: #Predicate { $0.tmdbID == tmdbID })
        d.fetchLimit = 1
        return try modelContext.fetch(d).first.map(DownloadRequestData.init)
    }

    public func delete(torrentID: String) throws {
        guard let row = try fetchOne(torrentID: torrentID) else { return }
        modelContext.delete(row)
        try modelContext.save()
    }

    private func fetchOne(torrentID key: String) throws -> DownloadRequest? {
        var d = FetchDescriptor<DownloadRequest>(predicate: #Predicate { $0.torrentID == key })
        d.fetchLimit = 1
        return try modelContext.fetch(d).first
    }
}
```

- [ ] **Step 5: Run the test, verify it passes**

Run: `cd Packages/DebridCore && swift test --filter DownloadsStoreTests`
Expected: PASS (3 tests).

- [ ] **Step 6: Full suite (SwiftData suites must stay green together)**

Run: `cd Packages/DebridCore && swift test`
Expected: all pass, no SIGSEGV (the new suite is under `SwiftDataSuite`).

- [ ] **Step 7: Commit**

```bash
git add Packages/DebridCore/Sources/DebridCore/Downloads/DownloadRequest.swift \
        Packages/DebridCore/Sources/DebridCore/Downloads/DownloadsStore.swift \
        Packages/DebridCore/Tests/DebridCoreTests/DownloadsStoreTests.swift
git commit -m "feat(core): persist download requests (DownloadsStore, SwiftData)"
```

---

## Task 6: `DownloadMonitor` — poll active requests once, map to statuses, clear terminal records

**Files:**
- Create: `Packages/DebridCore/Sources/DebridCore/Downloads/DownloadMonitor.swift`
- Test: `Packages/DebridCore/Tests/DebridCoreTests/DownloadMonitorTests.swift` (create)

`poll()` reads the store's active requests, fetches each torrent's `info`, maps to `DownloadStatus`, and **deletes the record** when a request is `.ready` or `.failed` (so it stops being tracked; a `.ready` title now lives in the normal library). Returns the statuses for this pass. A per-torrent info error is skipped (kept for the next pass).

- [ ] **Step 1: Write the failing test**

Create `Packages/DebridCore/Tests/DebridCoreTests/DownloadMonitorTests.swift`:

```swift
import Testing
import Foundation
import SwiftData
@testable import DebridCore

extension SwiftDataSuite {
    @Suite struct DownloadMonitorTests {
        private func store(seed: [DownloadRequestData]) async throws -> DownloadsStore {
            let c = try ModelContainer(for: DownloadRequest.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            let s = DownloadsStore(modelContainer: c)
            for r in seed { try await s.upsert(r) }
            return s
        }
        private func data(_ tid: String, _ tmdb: Int) -> DownloadRequestData {
            DownloadRequestData(torrentID: tid, tmdbID: tmdb, infoHash: "h", kind: .movie,
                                title: "t", requestedAt: Date(timeIntervalSince1970: 0))
        }
        private func info(_ id: String, _ status: String, _ progress: Double) -> TorrentInfo {
            TorrentInfo(id: id, filename: "f", hash: "h", bytes: 1, progress: progress,
                        status: status, files: [], links: [], added: nil)
        }

        @Test func reportsProgressAndKeepsDownloadingRecord() async throws {
            let s = try await store(seed: [data("A", 1)])
            let infos = FakeInfo(["A": info("A", "downloading", 30)])
            let monitor = DownloadMonitor(info: infos, store: s)
            let statuses = try await monitor.poll()
            #expect(statuses.count == 1)
            #expect(statuses[0].phase == .downloading)
            #expect(abs(statuses[0].fraction - 0.30) < 0.0001)
            #expect(try await s.all().count == 1)   // still tracked
        }

        @Test func clearsReadyAndFailedRecords() async throws {
            let s = try await store(seed: [data("A", 1), data("B", 2)])
            let infos = FakeInfo(["A": info("A", "downloaded", 100), "B": info("B", "dead", 0)])
            let monitor = DownloadMonitor(info: infos, store: s)
            let statuses = try await monitor.poll()
            #expect(Set(statuses.map(\.phase)) == [.ready, .failed("dead")])
            #expect(try await s.all().isEmpty)       // both terminal records cleared
        }

        @Test func skipsRequestWhoseInfoFails() async throws {
            let s = try await store(seed: [data("A", 1)])
            let infos = FakeInfo([:])   // no entry → info throws
            let monitor = DownloadMonitor(info: infos, store: s)
            let statuses = try await monitor.poll()
            #expect(statuses.isEmpty)
            #expect(try await s.all().count == 1)    // kept for next pass
        }
    }
}

private struct FakeInfo: DownloadInfoProviding {
    let map: [String: TorrentInfo]
    init(_ map: [String: TorrentInfo]) { self.map = map }
    func info(id: String) async throws -> TorrentInfo {
        guard let i = map[id] else { throw FakeInfoError.missing }
        return i
    }
}
private enum FakeInfoError: Error { case missing }
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `cd Packages/DebridCore && swift test --filter DownloadMonitorTests`
Expected: FAIL — no `DownloadMonitor` / `DownloadInfoProviding`.

- [ ] **Step 3: Implement the monitor + info seam**

Create `Packages/DebridCore/Sources/DebridCore/Downloads/DownloadMonitor.swift`:

```swift
import Foundation

/// Minimal seam over RD torrent info, so the monitor is testable without the network.
public protocol DownloadInfoProviding: Sendable {
    func info(id: String) async throws -> TorrentInfo
}

extension TorrentsClient: DownloadInfoProviding {}

/// Polls the active download requests against RD and reports their progress. When a request
/// reaches a terminal phase (`.ready` or `.failed`) its record is removed — a `.ready` title now
/// appears in the normal library; a `.failed` one is surfaced to the caller for "try another".
public actor DownloadMonitor {
    private let info: any DownloadInfoProviding
    private let store: DownloadsStore

    public init(info: any DownloadInfoProviding, store: DownloadsStore) {
        self.info = info
        self.store = store
    }

    /// One pass over all active requests. Returns this pass's statuses (terminal ones included so
    /// the caller can react/notify). A request whose info fetch fails is skipped and left tracked.
    @discardableResult
    public func poll() async throws -> [DownloadStatus] {
        let requests = try await store.all()
        var statuses: [DownloadStatus] = []
        for request in requests {
            guard let i = try? await info.info(id: request.torrentID) else { continue }
            let status = DownloadStatus(from: i, tmdbID: request.tmdbID)
            statuses.append(status)
            switch status.phase {
            case .ready, .failed:
                try? await store.delete(torrentID: request.torrentID)
            case .queued, .downloading:
                break
            }
        }
        return statuses
    }
}
```

- [ ] **Step 4: Run the test, verify it passes**

Run: `cd Packages/DebridCore && swift test --filter DownloadMonitorTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Packages/DebridCore/Sources/DebridCore/Downloads/DownloadMonitor.swift \
        Packages/DebridCore/Tests/DebridCoreTests/DownloadMonitorTests.swift
git commit -m "feat(core): DownloadMonitor polls requests, reports progress, clears terminal"
```

---

## Task 7: Compose in `AppSession`

**Files:**
- Modify: `Shared/DebridUI/Sources/DebridUI/Shell/AppSession.swift`

Wire the new brain pieces at sign-in so Slice 2's view-models can consume them. Add private refs (made `internal`/`public` as Slice 2 needs them — keep them `private` for now and expose in Slice 2). Build a `DownloadsStore` from its own in-memory-capable container, a `RealDebridDownloadService`, and a `DownloadMonitor`. The `streamSource` already exists and now supports `includeUncached`.

- [ ] **Step 1: Add stored properties**

In `AppSession`, near `private var streamSource` / `addService`, add:

```swift
    /// Stage-3 (Request Download) seams, composed at sign-in (nil while signed out).
    private var downloadService: DownloadRequesting?
    private var downloadsStore: DownloadsStore?
    private var downloadMonitor: DownloadMonitor?
```

- [ ] **Step 2: Compose them in `enterSignedIn()`**

After the `addService = RealDebridAddService(torrents: torrents)` line, add:

```swift
        downloadService = RealDebridDownloadService(torrents: torrents)
        if let container = try? ModelContainer(for: DownloadRequest.self) {
            let dStore = DownloadsStore(modelContainer: container)
            downloadsStore = dStore
            downloadMonitor = DownloadMonitor(info: torrents, store: dStore)
        }
```

- [ ] **Step 3: Reset them in `enterSignedOut()`**

In `enterSignedOut()`, alongside the other `= nil` resets, add:

```swift
        downloadService = nil
        downloadsStore = nil
        downloadMonitor = nil
```

- [ ] **Step 4: Build DebridUI (sources) + DebridCore**

Run:
```bash
cd Packages/DebridCore && swift build 2>&1 | grep -i warning; echo "core ${PIPESTATUS[0]}"
cd ../../Shared/DebridUI && swift build 2>&1 | grep -i warning; echo "ui ${PIPESTATUS[0]}"
```
Expected: both build, no warnings. (If the owner's parallel WIP breaks the DebridUI *test* target, that's unrelated — `swift build` of sources is the gate here.)

- [ ] **Step 5: Full DebridCore suite + DebridUI suite**

Run: `cd Packages/DebridCore && swift test 2>&1 | tail -3`
Then: `cd ../../Shared/DebridUI && swift test 2>&1 | tail -3` (if the suite compiles; if blocked by unrelated owner WIP, note it and rely on `swift build`).
Expected: green.

- [ ] **Step 6: Commit**

```bash
git add Shared/DebridUI/Sources/DebridUI/Shell/AppSession.swift
git commit -m "feat(ui): compose download service + store + monitor in AppSession"
```

---

## Self-Review Notes

- **Spec coverage:** uncached discovery (Task 2) · request-download keep-torrent (Task 3) · best-pick + try-another **reuses existing `[CachedStream].rankedFor`/`bestMatch`** (no new ranker — DRY; the orchestration that walks the ranked list lives in Slice 2's view-model) · progress mapping (Task 4) · persisted requests surviving restart (Task 5) · monitor progress→completion→failure + record clearing (Task 6) · composition (Task 7) · the make-or-break Comet spike (Task 1, gate before Slice 2). Notifications + UI are Slices 2–3, not here.
- **Type consistency:** `DownloadStatus.Phase` (`queued`/`downloading`/`ready`/`failed`), `DownloadStatus(from:tmdbID:)`, `DownloadRequestData(torrentID:tmdbID:infoHash:kind:title:requestedAt:)`, `DownloadsStore.upsert/all/find/delete`, `DownloadInfoProviding.info(id:)`, `DownloadRequesting.startDownload(infoHash:)`, `TorrentsClient.addForDownload(magnetHash:maxListAttempts:pollInterval:sleep:)`, `StreamSource.streams(for:includeUncached:)` — used consistently across tasks.
- **Verify-before-code reminders:** Tasks 4 & 6 tell the implementer to confirm the real `TorrentInfo` initializer labels before using the test helper (don't invent fields). Task 2's config-decoding assumes the base64 segment is the first path component — verified against `CometStreamSource`'s URL shape.
- **Scope:** brain only; each task ships a self-contained, tested unit. Slice 2 (UI + foreground notification) and Slice 3 (background notification) are separate plans, gated on Task 1.
