# LibraryBuilder: domain model + grouping — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `DebridCore`'s library **domain model** (`MediaItem` / `Season` / `Episode` / `MediaSource`) and a pure `LibraryBuilder.group(_:)` that turns a list of `TorrentInfo` into an organized library — Movies, and Shows → Seasons → Episodes — handling single movies, single-episode torrents, and season packs, grouping episodes of the same show across torrents.

**Architecture:** Pure, synchronous, dependency-free grouping (no networking). `LibraryBuilder` parses each torrent's name with the existing `FilenameParser`, classifies it (movie / single episode / season pack), expands season-pack video files into episodes (parsing each file path for its episode number), and accumulates episodes per show (deduped by season+episode, seasons & episodes sorted). TMDB enrichment (real titles, posters, overviews) and the trivial RD-fetch glue are **out of scope** — they're Plan 5 and app-wiring respectively.

**Tech Stack:** Swift 6.3 (Swift 6 language mode), SPM, Swift Testing.

**Plan 4 of the Seret roadmap.** Next: Plan 5 — TMDB enrichment of the grouped library + subtitles/persistence/player-protocol.

> **v1 scope notes (intentional, documented):** each movie torrent becomes its own `MediaItem` (version-merging of the same film across qualities is a later refinement). Show grouping is by normalized title only (TMDB-assisted disambiguation comes with enrichment). Metadata fields (`tmdbID`/`posterPath`/`overview`/…) are `nil` after grouping — Plan 5 fills them.

---

## File Structure

| File | Responsibility |
|---|---|
| `Sources/DebridCore/Library/MediaItem.swift` | `MediaKind`, `MediaSource`, `Episode`, `Season`, `MediaItem` value types |
| `Sources/DebridCore/Library/LibraryBuilder.swift` | Pure `group(_ infos: [TorrentInfo]) -> [MediaItem]` |
| `Tests/DebridCoreTests/MediaItemTests.swift` | Model construction + `Identifiable` ids (pure suite) |
| `Tests/DebridCoreTests/LibraryBuilderTests.swift` | Grouping table (pure suite) |

Both test suites are **plain top-level structs** (no networking → not nested under `MockTests`).

---

## Task 1: Library domain model

**Files:**
- Create: `Packages/DebridCore/Sources/DebridCore/Library/MediaItem.swift`
- Create: `Packages/DebridCore/Tests/DebridCoreTests/MediaItemTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/DebridCoreTests/MediaItemTests.swift`:
```swift
import Testing
@testable import DebridCore

struct MediaItemTests {
    private func source(_ torrentID: String = "T") -> MediaSource {
        MediaSource(torrentID: torrentID, fileID: 1, restrictedLink: "https://rd/x",
                    parsed: ParsedRelease(title: "X"))
    }

    @Test func episodeIDCombinesSeasonAndNumber() {
        let ep = Episode(season: 2, number: 5, source: source())
        #expect(ep.id == "s2e5")
        #expect(ep.season == 2)
        #expect(ep.number == 5)
    }

    @Test func seasonIDIsItsNumber() {
        let season = Season(number: 3, episodes: [])
        #expect(season.id == 3)
    }

    @Test func buildsAMovieItem() {
        let item = MediaItem(id: "movie:x", kind: .movie, title: "X", year: 2024,
                             sources: [source()], seasons: [])
        #expect(item.kind == .movie)
        #expect(item.sources.count == 1)
        #expect(item.seasons.isEmpty)
    }

    @Test func buildsAShowItem() {
        let ep = Episode(season: 1, number: 1, source: source())
        let item = MediaItem(id: "show:x", kind: .show, title: "X", year: nil,
                             sources: [], seasons: [Season(number: 1, episodes: [ep])])
        #expect(item.kind == .show)
        #expect(item.seasons.first?.episodes.first?.id == "s1e1")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path Packages/DebridCore --filter MediaItemTests`
Expected: FAIL — types not defined.

- [ ] **Step 3: Implement `MediaItem.swift`**

```swift
import Foundation

public enum MediaKind: String, Sendable, Equatable, Codable {
    case movie, show
}

/// A specific playable thing in Real-Debrid: a torrent (and, for packs, a file within it),
/// its restricted link (unrestrict at play time), and the parse used for quality display.
public struct MediaSource: Sendable, Equatable {
    public let torrentID: String
    public let fileID: Int?
    public let restrictedLink: String
    public let parsed: ParsedRelease

    public init(torrentID: String, fileID: Int?, restrictedLink: String, parsed: ParsedRelease) {
        self.torrentID = torrentID
        self.fileID = fileID
        self.restrictedLink = restrictedLink
        self.parsed = parsed
    }
}

public struct Episode: Sendable, Equatable, Identifiable {
    public let season: Int
    public let number: Int
    public let source: MediaSource

    public init(season: Int, number: Int, source: MediaSource) {
        self.season = season
        self.number = number
        self.source = source
    }

    public var id: String { "s\(season)e\(number)" }
}

public struct Season: Sendable, Equatable, Identifiable {
    public let number: Int
    public let episodes: [Episode]   // sorted by episode number

    public init(number: Int, episodes: [Episode]) {
        self.number = number
        self.episodes = episodes
    }

    public var id: Int { number }
}

/// A top-level library entry: a movie or a show. Metadata fields are nil until TMDB
/// enrichment (Plan 5). A movie carries `sources` (1+); a show carries `seasons`.
public struct MediaItem: Sendable, Equatable, Identifiable {
    public let id: String
    public let kind: MediaKind
    public let title: String
    public let year: Int?
    public let sources: [MediaSource]
    public let seasons: [Season]
    public let tmdbID: Int?
    public let posterPath: String?
    public let backdropPath: String?
    public let overview: String?

    public init(id: String, kind: MediaKind, title: String, year: Int?,
                sources: [MediaSource], seasons: [Season],
                tmdbID: Int? = nil, posterPath: String? = nil,
                backdropPath: String? = nil, overview: String? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.year = year
        self.sources = sources
        self.seasons = seasons
        self.tmdbID = tmdbID
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.overview = overview
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path Packages/DebridCore --filter MediaItemTests`
Expected: PASS (4 tests). Full suite → 46 tests. No warnings.

- [ ] **Step 5: Commit**

```bash
git add Packages/DebridCore
git commit -m "feat(core): library domain model (MediaItem/Season/Episode/MediaSource)"
```

---

## Task 2: LibraryBuilder — movies + single-episode shows

**Files:**
- Create: `Packages/DebridCore/Sources/DebridCore/Library/LibraryBuilder.swift`
- Create: `Packages/DebridCore/Tests/DebridCoreTests/LibraryBuilderTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/DebridCoreTests/LibraryBuilderTests.swift`:
```swift
import Testing
@testable import DebridCore

struct LibraryBuilderTests {
    let builder = LibraryBuilder()

    /// One torrent with a single selected video file named `path`.
    private func torrent(_ id: String, name: String, file path: String) -> TorrentInfo {
        TorrentInfo(id: id, filename: name, hash: "h", bytes: 1000, progress: 100, status: "downloaded",
                    files: [TorrentFile(id: 1, path: path, bytes: 1000, selected: 1)],
                    links: ["https://rd/\(id)"])
    }

    @Test func groupsAMovie() {
        let lib = builder.group([
            torrent("A", name: "Dune.Part.Two.2024.2160p.BluRay.x265-WiKi.mkv", file: "/Dune/movie.mkv"),
        ])
        #expect(lib.count == 1)
        #expect(lib[0].kind == .movie)
        #expect(lib[0].title == "Dune Part Two")
        #expect(lib[0].year == 2024)
        #expect(lib[0].sources.first?.restrictedLink == "https://rd/A")
    }

    @Test func groupsSingleEpisodesOfTheSameShowAcrossTorrents() {
        let lib = builder.group([
            torrent("E1", name: "Shogun.S01E01.1080p.WEB-DL.x265-NTb.mkv", file: "/Shogun/e01.mkv"),
            torrent("E2", name: "Shogun.S01E02.1080p.WEB-DL.x265-NTb.mkv", file: "/Shogun/e02.mkv"),
        ])
        #expect(lib.count == 1)
        let show = lib[0]
        #expect(show.kind == .show)
        #expect(show.title == "Shogun")
        #expect(show.seasons.count == 1)
        #expect(show.seasons[0].number == 1)
        #expect(show.seasons[0].episodes.map(\.number) == [1, 2])
    }

    @Test func separatesMoviesAndShows() {
        let lib = builder.group([
            torrent("M", name: "The.Batman.2022.1080p.BluRay.x264-GRP.mkv", file: "/b/movie.mkv"),
            torrent("E1", name: "Severance.S02E01.1080p.x265-NTb.mkv", file: "/s/e01.mkv"),
        ])
        #expect(lib.contains { $0.kind == .movie && $0.title == "The Batman" })
        #expect(lib.contains { $0.kind == .show && $0.title == "Severance" })
        #expect(lib.count == 2)
    }

    @Test func dedupesRepeatedEpisode() {
        let lib = builder.group([
            torrent("E1", name: "Shogun.S01E01.1080p.x265-A.mkv", file: "/a/e01.mkv"),
            torrent("E1b", name: "Shogun.S01E01.2160p.x265-B.mkv", file: "/b/e01.mkv"),
        ])
        #expect(lib.count == 1)
        #expect(lib[0].seasons[0].episodes.count == 1)   // same s1e1 kept once
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path Packages/DebridCore --filter LibraryBuilderTests`
Expected: FAIL — `LibraryBuilder` not defined.

- [ ] **Step 3: Implement `LibraryBuilder.swift`** (movies + single episodes; season-pack branch is added in Task 3)

```swift
import Foundation

/// Turns Real-Debrid torrents into an organized library. Pure and synchronous —
/// parses each torrent name, classifies it, and groups episodes per show.
/// TMDB enrichment and RD fetching live elsewhere (Plan 5 / app layer).
public struct LibraryBuilder: Sendable {
    private let parser: FilenameParser

    public init(parser: FilenameParser = FilenameParser()) {
        self.parser = parser
    }

    public func group(_ infos: [TorrentInfo]) -> [MediaItem] {
        var movies: [MediaItem] = []
        var shows: [String: ShowAccumulator] = [:]

        for info in infos {
            let parsed = parser.parse(info.filename)
            if parsed.isTV {
                let key = Self.titleKey(parsed.title)
                let acc = shows[key] ?? ShowAccumulator(title: parsed.title, year: parsed.year)
                ingestTV(info, parsed, into: acc)
                shows[key] = acc
            } else if let primary = info.primaryVideoFile() {
                let source = MediaSource(torrentID: info.id, fileID: primary.file.id,
                                         restrictedLink: primary.link, parsed: parsed)
                movies.append(MediaItem(
                    id: "movie:\(Self.titleKey(parsed.title)):\(parsed.year.map(String.init) ?? "")",
                    kind: .movie, title: parsed.title, year: parsed.year,
                    sources: [source], seasons: []))
            }
        }

        let movieItems = movies.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        let showItems = shows.values.map { $0.build() }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        return movieItems + showItems
    }

    /// Adds a torrent's episode(s) to a show accumulator. Task 2 handles single episodes;
    /// Task 3 adds season-pack expansion.
    private func ingestTV(_ info: TorrentInfo, _ parsed: ParsedRelease, into acc: ShowAccumulator) {
        if let episode = parsed.episode, let primary = info.primaryVideoFile() {
            acc.add(season: parsed.season ?? 1, number: episode,
                    source: MediaSource(torrentID: info.id, fileID: primary.file.id,
                                        restrictedLink: primary.link, parsed: parsed))
        }
    }

    /// Normalized grouping key: lowercased letters+digits only, so "Dune.Part.Two"
    /// and "Dune Part Two" collapse together.
    static func titleKey(_ title: String) -> String {
        title.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

/// Mutable accumulator for a single show's episodes (deduped by season+episode).
final class ShowAccumulator {
    let title: String
    let year: Int?
    private var episodes: [String: Episode] = [:]

    init(title: String, year: Int?) {
        self.title = title
        self.year = year
    }

    func add(season: Int, number: Int, source: MediaSource) {
        let episode = Episode(season: season, number: number, source: source)
        if episodes[episode.id] == nil { episodes[episode.id] = episode }   // keep first
    }

    func build() -> MediaItem {
        let bySeason = Dictionary(grouping: episodes.values, by: { $0.season })
        let seasons = bySeason.keys.sorted().map { number in
            Season(number: number, episodes: bySeason[number]!.sorted { $0.number < $1.number })
        }
        return MediaItem(id: "show:\(LibraryBuilder.titleKey(title))", kind: .show,
                         title: title, year: year, sources: [], seasons: seasons)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path Packages/DebridCore --filter LibraryBuilderTests`
Expected: PASS (4 tests). Full suite → 50 tests. No warnings.

- [ ] **Step 5: Commit**

```bash
git add Packages/DebridCore
git commit -m "feat(core): LibraryBuilder.group — movies + single-episode shows"
```

---

## Task 3: LibraryBuilder — season packs

**Files:**
- Modify: `Packages/DebridCore/Sources/DebridCore/Library/LibraryBuilder.swift`
- Modify: `Packages/DebridCore/Tests/DebridCoreTests/LibraryBuilderTests.swift`

- [ ] **Step 1: Write the failing tests** (add inside `LibraryBuilderTests`)

```swift
    /// One torrent with several selected video files (a season pack).
    private func pack(_ id: String, name: String, files: [String]) -> TorrentInfo {
        let tfiles = files.enumerated().map { i, path in
            TorrentFile(id: i + 1, path: path, bytes: 1000, selected: 1)
        }
        let links = files.indices.map { "https://rd/\(id)/\($0)" }
        return TorrentInfo(id: id, filename: name, hash: "h", bytes: 3000, progress: 100,
                           status: "downloaded", files: tfiles, links: links)
    }

    @Test func expandsASeasonPackIntoEpisodes() {
        let lib = builder.group([
            pack("P", name: "Fallout.S01.2160p.WEB-DL.HEVC-FLUX", files: [
                "/Fallout.S01/Fallout.S01E01.mkv",
                "/Fallout.S01/Fallout.S01E02.mkv",
                "/Fallout.S01/Fallout.S01E03.mkv",
            ]),
        ])
        #expect(lib.count == 1)
        let show = lib[0]
        #expect(show.kind == .show)
        #expect(show.title == "Fallout")
        #expect(show.seasons.count == 1)
        #expect(show.seasons[0].episodes.map(\.number) == [1, 2, 3])
        // each episode points at its own file link
        #expect(show.seasons[0].episodes[0].source.restrictedLink == "https://rd/P/0")
        #expect(show.seasons[0].episodes[1].source.restrictedLink == "https://rd/P/1")
    }

    @Test func mergesAPackAndASingleEpisodeIntoOneShow() {
        let lib = builder.group([
            pack("P", name: "Fallout.S01.2160p.WEB-DL.HEVC-FLUX", files: [
                "/Fallout.S01/Fallout.S01E01.mkv",
                "/Fallout.S01/Fallout.S01E02.mkv",
            ]),
            torrent("X", name: "Fallout.S01E03.2160p.WEB-DL.HEVC-NTb.mkv", file: "/x/e03.mkv"),
        ])
        #expect(lib.count == 1)
        #expect(lib[0].seasons[0].episodes.map(\.number) == [1, 2, 3])
    }

    @Test func skipsNonVideoFilesInAPack() {
        let lib = builder.group([
            pack("P", name: "Fallout.S01.WEB-DL", files: [
                "/Fallout.S01/Fallout.S01E01.mkv",
                "/Fallout.S01/readme.txt",
                "/Fallout.S01/Fallout.S01E02.mkv",
            ]),
        ])
        #expect(lib[0].seasons[0].episodes.map(\.number) == [1, 2])   // .txt ignored
    }
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path Packages/DebridCore --filter LibraryBuilderTests`
Expected: FAIL — season packs not yet expanded (`Fallout.S01` parses with a season but no episode, so `ingestTV` currently adds nothing → assertions fail).

- [ ] **Step 3: Extend `ingestTV` to expand season packs**

Replace the `ingestTV` method with:
```swift
    /// Adds a torrent's episode(s) to a show accumulator: a single-episode torrent
    /// contributes one episode; a season pack (season but no episode in the torrent name)
    /// is expanded by parsing each selected video file path for its episode number.
    private func ingestTV(_ info: TorrentInfo, _ parsed: ParsedRelease, into acc: ShowAccumulator) {
        if let episode = parsed.episode, let primary = info.primaryVideoFile() {
            acc.add(season: parsed.season ?? 1, number: episode,
                    source: MediaSource(torrentID: info.id, fileID: primary.file.id,
                                        restrictedLink: primary.link, parsed: parsed))
            return
        }
        // Season pack: expand selected video files.
        let packSeason = parsed.season ?? 1
        for (file, link) in info.selectedFilesWithLinks() where Self.isVideoPath(file.path) {
            let fileParsed = parser.parse(file.path)
            guard let episode = fileParsed.episode else { continue }
            acc.add(season: fileParsed.season ?? packSeason, number: episode,
                    source: MediaSource(torrentID: info.id, fileID: file.id,
                                        restrictedLink: link, parsed: fileParsed))
        }
    }

    private static func isVideoPath(_ path: String) -> Bool {
        let video: Set<String> = ["mkv", "mp4", "avi", "m4v", "mov", "ts", "wmv"]
        return video.contains(URL(fileURLWithPath: path).pathExtension.lowercased())
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path Packages/DebridCore --filter LibraryBuilderTests`
Expected: PASS (7 tests). Then full suite `swift test --package-path Packages/DebridCore` → 53 tests, stable (run twice). Confirm `swift build … | grep -i warning` is empty.

- [ ] **Step 5: Commit**

```bash
git add Packages/DebridCore
git commit -m "feat(core): LibraryBuilder season-pack expansion (files → episodes)"
```

---

## Done when

- [ ] `swift test --package-path Packages/DebridCore` green (~53 tests), stable, zero warnings.
- [ ] `DebridCore` exposes: `MediaKind`, `MediaSource`, `Episode`, `Season`, `MediaItem`, and `LibraryBuilder.group(_:)`.
- [ ] `group` correctly produces Movies and Shows→Seasons→Episodes from `[TorrentInfo]`, handling single movies, single episodes, season packs, cross-torrent show merging, dedup, and sorting; non-video pack files are ignored.
- [ ] Metadata fields stay nil (enrichment is Plan 5); no networking in this layer.
- [ ] All work committed.

**Next:** Plan 5 — TMDB enrichment (`LibraryBuilder.build(from:)` async: group → match each item to TMDB → fill title/poster/backdrop/overview), then the trivial RD-fetch glue, then on to subtitles + persistence + the player protocol.
