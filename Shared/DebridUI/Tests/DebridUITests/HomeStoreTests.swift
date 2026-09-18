import Testing
import Foundation
@testable import DebridUI
import DebridCore

private struct FakeWatch: WatchProgressProviding {
    var states: [WatchState]
    func recentlyWatched(limit: Int, profileID: String) async throws -> [WatchState] {
        Array(states.prefix(limit))
    }
    func progress(forContentKey key: String, profileID: String) async throws -> WatchState? { nil }
    func record(contentKey: String, sourceKey: String, positionSeconds: Double,
                durationSeconds: Double, finished: Bool, profileID: String) async throws {}
    func deleteProgress(forContentKeys keys: [String]) async throws {}
}

@Suite struct HomeStoreTests {
    @MainActor @Test func resolvesMovieAndShowProgress() async {
        let movie = MediaItem(id: "movie:dune:2021", kind: .movie, title: "Dune", year: 2021, sources: [], seasons: [])
        let show  = MediaItem(id: "show:bb", kind: .show, title: "Breaking Bad", year: 2008, sources: [], seasons: [])
        let states = [
            WatchState(contentKey: "movie:dune:2021", sourceKey: "t#f", positionSeconds: 30, durationSeconds: 120, finished: false, updatedAt: Date()),
            WatchState(contentKey: "show:bb:s3e4", sourceKey: "t#f", positionSeconds: 600, durationSeconds: 1200, finished: false, updatedAt: Date()),
        ]
        let store = HomeStore(watch: FakeWatch(states: states))
        store.activeProfileID = "p1"
        await store.rebuild(movies: [movie], shows: [show])
        #expect(store.continueWatching.count == 2)
        #expect(store.continueWatching[0].item.id == "movie:dune:2021")
        #expect(abs(store.continueWatching[0].fraction - 0.25) < 0.001)
        #expect(store.continueWatching[1].item.id == "show:bb")
        #expect(store.continueWatching[1].subtitle == "S3 · E4")
    }

    @MainActor @Test func resumeFromHomeResolvesTheExactEpisodeSourceAndPosition() async {
        let src = MediaSource(torrentID: "t9", fileID: 3, restrictedLink: "rd://ep",
                              parsed: ParsedRelease(title: "Invincible", season: 4, episode: 1, resolution: "2160p"))
        let episode = Episode(season: 4, number: 1, source: src)
        let show = MediaItem(id: "show:inv", kind: .show, title: "Invincible", year: 2021,
                             sources: [], seasons: [Season(number: 4, episodes: [episode])])
        let states = [WatchState(contentKey: "show:inv:s4e1", sourceKey: "t9#3",
                                 positionSeconds: 353, durationSeconds: 3000, finished: false, updatedAt: Date())]
        let store = HomeStore(watch: FakeWatch(states: states))
        store.activeProfileID = "p1"
        await store.rebuild(movies: [], shows: [show])

        let hi = store.continueWatching[0]
        #expect(hi.isResumable)
        let req = hi.playbackRequest()
        #expect(req?.source == src)                       // the exact episode file, not the show's first
        #expect(req?.episode == episode)
        #expect(req?.contentKey == "show:inv:s4e1")        // progress keys back to the same episode
        #expect(req?.resumeAt == 353)                      // resumes where it left off
        #expect(req?.fromStart == false)
        #expect(req?.label == "Invincible — S4·E1")
    }

    @MainActor @Test func finishedOrUnresolvedEntriesAreNotDirectlyResumable() async {
        // A show whose watched episode is no longer in the library (version removed) → no source.
        let show = MediaItem(id: "show:x", kind: .show, title: "X", year: nil, sources: [], seasons: [])
        let states = [WatchState(contentKey: "show:x:s1e1", sourceKey: "t#f",
                                 positionSeconds: 10, durationSeconds: 100, finished: false, updatedAt: Date())]
        let store = HomeStore(watch: FakeWatch(states: states))
        store.activeProfileID = "p1"
        await store.rebuild(movies: [], shows: [show])
        let hi = store.continueWatching[0]
        #expect(!hi.isResumable)                           // unresolved → UI falls back to Detail
        #expect(hi.playbackRequest() == nil)
    }

    @MainActor @Test func recentlyAddedSortsDescAndSkipsNil() async {
        let older = MediaItem(id: "a", kind: .movie, title: "A", year: nil, sources: [], seasons: [], addedAt: Date(timeIntervalSince1970: 1000))
        let newer = MediaItem(id: "b", kind: .movie, title: "B", year: nil, sources: [], seasons: [], addedAt: Date(timeIntervalSince1970: 2000))
        let undated = MediaItem(id: "c", kind: .movie, title: "C", year: nil, sources: [], seasons: [])
        let store = HomeStore(watch: FakeWatch(states: []))
        store.activeProfileID = "p1"
        await store.rebuild(movies: [older, newer, undated], shows: [])
        #expect(store.recentlyAdded.map(\.id) == ["b", "a"])
    }
}

/// Continue Watching is the screen the viewer actually resumes from, so it — not just the title
/// page's Play button — has to honour the version they chose. It used to resolve with the quality
/// ranker and never ask, so a chosen version was silently ignored on every resume.
@Suite struct HomeStoreVersionPreferenceTests {
    private final class FakePrefs: VersionPreferring, @unchecked Sendable {
        var stored: [String: String] = [:]
        func preferred(forContentKey key: String) async -> String? { stored[key] }
        func choose(contentKey: String, sourceKey: String) async { stored[contentKey] = sourceKey }
        func clear(contentKey: String) async { stored[contentKey] = nil }
    }

    private func source(_ torrentID: String, _ resolution: String) -> MediaSource {
        MediaSource(torrentID: torrentID, fileID: nil, restrictedLink: "l",
                    parsed: ParsedRelease(title: "T", resolution: resolution))
    }

    private func movie(_ sources: [MediaSource]) -> MediaItem {
        MediaItem(id: "movie:dune:2021", kind: .movie, title: "Dune", year: 2021,
                  sources: sources, seasons: [])
    }

    private func states() -> [WatchState] {
        [WatchState(contentKey: "movie:dune:2021", sourceKey: "t#f", positionSeconds: 30,
                    durationSeconds: 120, finished: false, updatedAt: Date())]
    }

    @MainActor @Test func resumeUsesTheChosenVersionNotTheRanker() async {
        let sd = source("sd", "1080p"), uhd = source("uhd", "2160p")
        let prefs = FakePrefs()
        prefs.stored["movie:dune:2021"] = WatchKey.source(sd)      // deliberately NOT the best
        let store = HomeStore(watch: FakeWatch(states: states()), versionPrefs: prefs)
        store.activeProfileID = "p1"
        await store.rebuild(movies: [movie([uhd, sd])], shows: [])
        #expect(store.continueWatching.first?.source?.torrentID == "sd")
    }

    @MainActor @Test func noPreferenceStillUsesTheRanker() async {
        let sd = source("sd", "1080p"), uhd = source("uhd", "2160p")
        let store = HomeStore(watch: FakeWatch(states: states()), versionPrefs: FakePrefs())
        store.activeProfileID = "p1"
        await store.rebuild(movies: [movie([sd, uhd])], shows: [])
        #expect(store.continueWatching.first?.source?.torrentID == "uhd")
    }

    /// A preference pointing at a torrent since deleted from RD must fall back, not break Resume.
    @MainActor @Test func aStalePreferenceFallsBackToTheRanker() async {
        let sd = source("sd", "1080p"), uhd = source("uhd", "2160p")
        let prefs = FakePrefs()
        prefs.stored["movie:dune:2021"] = "gone#0"
        let store = HomeStore(watch: FakeWatch(states: states()), versionPrefs: prefs)
        store.activeProfileID = "p1"
        await store.rebuild(movies: [movie([sd, uhd])], shows: [])
        #expect(store.continueWatching.first?.source?.torrentID == "uhd")
    }

    /// Recently Added is the library sorted by date — it has nothing to do with who is watching.
    /// Blanking it alongside Continue Watching meant a profile that never resolved left Home
    /// completely empty, including the one rail that could always have been filled.
    @MainActor @Test func recentlyAddedStillFillsWhenNoProfileHasResolved() async {
        let older = MediaItem(id: "movie:a", kind: .movie, title: "A", year: 2024, sources: [],
                              seasons: [], addedAt: Date(timeIntervalSince1970: 100))
        let newer = MediaItem(id: "movie:b", kind: .movie, title: "B", year: 2024, sources: [],
                              seasons: [], addedAt: Date(timeIntervalSince1970: 200))
        let store = HomeStore(watch: FakeWatch(states: []))
        store.activeProfileID = nil            // never resolved

        await store.rebuild(movies: [older, newer], shows: [])

        #expect(store.continueWatching.isEmpty)          // genuinely per-profile; correctly empty
        #expect(store.recentlyAdded.map(\.id) == ["movie:b", "movie:a"])
    }

    /// Every entry's chosen version comes from ONE read, not one per entry. Home rebuilds on the
    /// screen appearing, on movies and shows landing separately, on the profile resolving, on the
    /// player closing, and on every CloudKit import — a round-trip per rail entry each time.
    @MainActor @Test func chosenVersionsAreReadInOneBatch() async {
        actor CountingPrefs: VersionPreferring {
            private(set) var singleCalls = 0
            private(set) var batchCalls = 0
            func preferred(forContentKey key: String) async -> String? { singleCalls += 1; return nil }
            func preferred(forContentKeys keys: [String]) async -> [String: String] {
                batchCalls += 1
                return [:]
            }
            func choose(contentKey: String, sourceKey: String) async {}
            func clear(contentKey: String) async {}
        }
        let items = (1...5).map {
            MediaItem(id: "movie:\($0)", kind: .movie, title: "M\($0)", year: 2024,
                      sources: [], seasons: [])
        }
        let states = items.map {
            WatchState(contentKey: $0.id, sourceKey: "t#f", positionSeconds: 10,
                       durationSeconds: 100, finished: false, updatedAt: Date())
        }
        let prefs = CountingPrefs()
        let store = HomeStore(watch: FakeWatch(states: states), versionPrefs: prefs)
        store.activeProfileID = "p1"

        await store.rebuild(movies: items, shows: [])

        #expect(store.continueWatching.count == 5)
        #expect(await prefs.batchCalls == 1)
        #expect(await prefs.singleCalls == 0)
    }
}

/// Marking from the Continue Watching rail. The rail is the screen you actually remove a title
/// from — a film you opened for ten seconds sits at the top of Home until something clears it —
/// so the mark has to act on the entry's own key: the movie, or the ONE episode on the card.
@Suite struct HomeStoreWatchMarkTests {
    /// Models the store's real Continue-Watching rule (`!finished && positionSeconds > 0`) so a
    /// mark's effect on the rail is observable, not just its write.
    private final class RecordingWatch: WatchProgressProviding, @unchecked Sendable {
        private let lock = NSLock()
        private var rows: [String: WatchState] = [:]
        private(set) var writes: [(key: String, sourceKey: String, position: Double,
                                   duration: Double, finished: Bool, profileID: String)] = []

        init(_ states: [WatchState]) {
            rows = Dictionary(uniqueKeysWithValues: states.map { ($0.contentKey, $0) })
        }

        func recentlyWatched(limit: Int, profileID: String) async throws -> [WatchState] {
            lock.withLock {
                Array(rows.values
                    .filter { !$0.finished && $0.positionSeconds > 0 }
                    .sorted { $0.updatedAt > $1.updatedAt }
                    .prefix(limit))
            }
        }
        func progress(forContentKey key: String, profileID: String) async throws -> WatchState? {
            lock.withLock { rows[key] }
        }
        func record(contentKey: String, sourceKey: String, positionSeconds: Double,
                    durationSeconds: Double, finished: Bool, profileID: String) async throws {
            lock.withLock {
                writes.append((contentKey, sourceKey, positionSeconds, durationSeconds,
                               finished, profileID))
                rows[contentKey] = WatchState(contentKey: contentKey, sourceKey: sourceKey,
                                              positionSeconds: positionSeconds,
                                              durationSeconds: durationSeconds,
                                              finished: finished, updatedAt: Date())
            }
        }
        func deleteProgress(forContentKeys keys: [String]) async throws {}
    }

    private func show() -> MediaItem {
        let src = MediaSource(torrentID: "t9", fileID: 3, restrictedLink: "rd://ep",
                              parsed: ParsedRelease(title: "Invincible", season: 4, episode: 1,
                                                    resolution: "2160p"))
        return MediaItem(id: "show:inv", kind: .show, title: "Invincible", year: 2021, sources: [],
                         seasons: [Season(number: 4, episodes: [Episode(season: 4, number: 1,
                                                                        source: src)])])
    }

    private func movie() -> MediaItem {
        MediaItem(id: "movie:dune:2021", kind: .movie, title: "Dune", year: 2021,
                  sources: [MediaSource(torrentID: "t1", fileID: 1, restrictedLink: "rd://m",
                                        parsed: ParsedRelease(title: "Dune", resolution: "2160p"))],
                  seasons: [])
    }

    /// Marking WATCHED keeps the position and runtime — the entry is finished, not erased.
    @MainActor @Test func markingWatchedFinishesTheEntryAndDropsItFromTheRail() async {
        let watch = RecordingWatch([WatchState(contentKey: "movie:dune:2021", sourceKey: "t1#1",
                                               positionSeconds: 30, durationSeconds: 120,
                                               finished: false, updatedAt: Date())])
        let store = HomeStore(watch: watch)
        store.activeProfileID = "p1"
        await store.rebuild(movies: [movie()], shows: [])
        #expect(store.continueWatching.count == 1)

        await store.setWatched(true, entry: store.continueWatching[0])

        #expect(watch.writes.count == 1)
        #expect(watch.writes.first?.key == "movie:dune:2021")
        #expect(watch.writes.first?.finished == true)
        #expect(watch.writes.first?.position == 30)      // keeps where you were
        #expect(watch.writes.first?.duration == 120)
        #expect(watch.writes.first?.profileID == "p1")

        await store.rebuild(movies: [movie()], shows: [])
        #expect(store.continueWatching.isEmpty)
    }

    /// The reported case: started for a second, don't want it on Home. Unwatched clears the
    /// position, which is what takes it off the rail.
    @MainActor @Test func markingUnwatchedClearsThePositionAndDropsItFromTheRail() async {
        let watch = RecordingWatch([WatchState(contentKey: "movie:dune:2021", sourceKey: "t1#1",
                                               positionSeconds: 8, durationSeconds: 8000,
                                               finished: false, updatedAt: Date())])
        let store = HomeStore(watch: watch)
        store.activeProfileID = "p1"
        await store.rebuild(movies: [movie()], shows: [])

        await store.setWatched(false, entry: store.continueWatching[0])

        #expect(watch.writes.first?.key == "movie:dune:2021")
        #expect(watch.writes.first?.finished == false)
        #expect(watch.writes.first?.position == 0)       // start over
        #expect(watch.writes.first?.duration == 8000)    // runtime survives

        await store.rebuild(movies: [movie()], shows: [])
        #expect(store.continueWatching.isEmpty)
    }

    /// A show's rail entry carries the series as its `item`, so a mark keyed off `item.id` would
    /// hit the series row and leave the episode you were part-way through exactly where it was.
    @MainActor @Test func markingAShowEntryWritesTheEpisodeKeyNotTheSeriesKey() async {
        let watch = RecordingWatch([WatchState(contentKey: "show:inv:s4e1", sourceKey: "t9#3",
                                               positionSeconds: 353, durationSeconds: 3000,
                                               finished: false, updatedAt: Date())])
        let store = HomeStore(watch: watch)
        store.activeProfileID = "p1"
        await store.rebuild(movies: [], shows: [show()])
        #expect(store.continueWatching[0].item.id == "show:inv")

        await store.setWatched(true, entry: store.continueWatching[0])

        #expect(watch.writes.first?.key == "show:inv:s4e1")
        #expect(watch.writes.first?.sourceKey == "t9#3")
    }

    /// The card goes as the menu dismisses. The authoritative recompose belongs to the caller —
    /// this store has no library to rebuild from — so without this the viewer watches the entry
    /// they just cleared sit on the rail, and in the hero, until a round-trip finishes.
    @MainActor @Test func theEntryLeavesTheRailWithoutWaitingForARebuild() async {
        let watch = RecordingWatch([WatchState(contentKey: "movie:dune:2021", sourceKey: "t1#1",
                                               positionSeconds: 8, durationSeconds: 8000,
                                               finished: false, updatedAt: Date()),
                                    WatchState(contentKey: "show:inv:s4e1", sourceKey: "t9#3",
                                               positionSeconds: 353, durationSeconds: 3000,
                                               finished: false, updatedAt: Date().addingTimeInterval(-9))])
        let store = HomeStore(watch: watch)
        store.activeProfileID = "p1"
        await store.rebuild(movies: [movie()], shows: [show()])
        #expect(store.continueWatching.count == 2)
        #expect(store.featured?.contentKey == "movie:dune:2021")

        await store.setWatched(false, entry: store.continueWatching[0])

        // No rebuild in between.
        #expect(store.continueWatching.map(\.contentKey) == ["show:inv:s4e1"])
        #expect(store.featured?.contentKey == "show:inv:s4e1")   // the hero follows the rail
    }

    /// Nothing is written before the profile resolves — a mark keyed to "" would be adopted by no
    /// one and would never take the card off the rail.
    @MainActor @Test func aMarkBeforeTheProfileResolvesWritesNothing() async {
        let watch = RecordingWatch([WatchState(contentKey: "movie:dune:2021", sourceKey: "t1#1",
                                               positionSeconds: 30, durationSeconds: 120,
                                               finished: false, updatedAt: Date())])
        let store = HomeStore(watch: watch)
        store.activeProfileID = "p1"
        await store.rebuild(movies: [movie()], shows: [])
        let entry = store.continueWatching[0]

        store.activeProfileID = nil
        await store.setWatched(true, entry: entry)

        #expect(watch.writes.isEmpty)
    }
}

/// Recently Added is a full grid on tvOS, not a rail you nudge sideways — it holds ten rows of six.
@Suite struct HomeStoreRecentlyAddedLimitTests {
    @MainActor @Test func recentlyAddedHoldsSixtyNewestByDefault() async {
        let items = (1...65).map {
            MediaItem(id: "movie:\($0)", kind: .movie, title: "M\($0)", year: 2024, sources: [],
                      seasons: [], addedAt: Date(timeIntervalSince1970: Double($0)))
        }
        let store = HomeStore(watch: FakeWatch(states: []))
        store.activeProfileID = "p1"

        await store.rebuild(movies: items, shows: [])

        #expect(store.recentlyAdded.count == 60)
        #expect(store.recentlyAdded.first?.id == "movie:65")   // newest first
        #expect(store.recentlyAdded.last?.id == "movie:6")     // the five oldest fall off
    }

    /// The iPhone rail asks for fewer, and a test fixture asks for a handful.
    @MainActor @Test func theLimitIsSettable() async {
        let items = (1...10).map {
            MediaItem(id: "movie:\($0)", kind: .movie, title: "M\($0)", year: 2024, sources: [],
                      seasons: [], addedAt: Date(timeIntervalSince1970: Double($0)))
        }
        let store = HomeStore(watch: FakeWatch(states: []), recentlyAddedLimit: 3)
        store.activeProfileID = "p1"

        await store.rebuild(movies: items, shows: [])

        #expect(store.recentlyAdded.map(\.id) == ["movie:10", "movie:9", "movie:8"])
    }
}
