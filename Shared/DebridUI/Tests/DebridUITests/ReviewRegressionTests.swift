import Testing
import Foundation
import SwiftData
import DebridCore
@testable import DebridUI

// Regressions found by reviewing fix/polish-sweep-2026-10-01 against itself. Each #expect states
// the behaviour a viewer would expect; every one failed on the branch before its fix.

private final class LogReq: DownloadRequesting, @unchecked Sendable {
    private(set) var calls: [String] = []
    func startDownload(infoHash: String) async throws -> TorrentInfo {
        calls.append(infoHash)
        return TorrentInfo(id: "T-\(infoHash.prefix(4))", filename: "M", hash: infoHash, bytes: 1,
                           progress: 10, status: "downloading",
                           files: [TorrentFile(id: 1, path: "/M/m.mkv", bytes: 1, selected: 1)],
                           links: [])
    }
}
private final class NoRecs: DownloadRecording, @unchecked Sendable {
    func upsert(_ data: DownloadRequestData) async throws {}
    func all() async throws -> [DownloadRequestData] { [] }
    func delete(torrentID: String) async throws {}
}
private final class NoPoll: DownloadPolling, @unchecked Sendable {
    func poll() async throws -> [DownloadStatus] { [] }
}
private final class NoDel: DownloadDeleting, @unchecked Sendable {
    func deleteTorrent(id: String) async throws {}
}
private func cs(_ hash: String) -> CachedStream {
    CachedStream(infoHash: hash, fileIdx: nil, rawTitle: "t",
                 parsed: ParsedRelease(title: "t", resolution: "1080p"),
                 languages: ["en"], sizeBytes: 1, sourceName: nil)
}

private enum Boom: Error { case nope }
private struct ListsSeason: MediaDetailsProviding {
    var episodes: [TMDBEpisodeDetails] = []
    func movieDetails(tmdbID: Int) async throws -> TMDBMovieDetails { throw Boom.nope }
    func tvDetails(tmdbID: Int) async throws -> TMDBTVDetails { throw Boom.nope }
    func seasonEpisodes(tvID: Int, season: Int) async throws -> [TMDBEpisodeDetails] { episodes }
}

private func src(_ id: String) -> MediaSource {
    MediaSource(torrentID: id, fileID: nil, restrictedLink: "rd://\(id)",
                parsed: ParsedRelease(title: "t", resolution: "1080p"))
}
private func show(_ tmdb: Int, seasons: [Int: Int]) -> MediaItem {
    MediaItem(id: "show:tmdb:\(tmdb)", kind: .show, title: "Show\(tmdb)", year: 2020, sources: [],
              seasons: seasons.keys.sorted().map { s in
                  Season(number: s, episodes: (1...seasons[s]!).map { n in
                      Episode(season: s, number: n, source: src("t\(tmdb)-\(s)-\(n)"))
                  })
              }, tmdbID: tmdb)
}

extension SwiftDataSuite {
    @Suite struct ReviewRegressionTests {
        private func provider() throws -> LocalWatchProvider {
            let c = try ModelContainer(for: WatchProgress.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            return LocalWatchProvider(store: LocalWatchStore(modelContainer: c), profileID: { "p1" })
        }

        // F1 — a second version / a pasted magnet while one download runs.
        @MainActor @Test func anotherVersionOrAMagnetDuringADownloadIsSent() async {
            let req = LogReq()
            let store = DownloadStore(service: req, records: NoRecs(), poller: NoPoll(), deleter: NoDel(),
                                      pollInterval: .seconds(3600))
            await store.request(contentKey: "movie:1", tmdbID: 1, title: "M", kind: .movie,
                                candidates: [cs(String(repeating: "a", count: 40))])
            // The Versions list's "Download" on a different release — VersionsModel.pick does exactly this.
            await store.request(contentKey: "movie:1", tmdbID: 1, title: "M", kind: .movie,
                                candidates: [cs(String(repeating: "b", count: 40))])
            #expect(req.calls.count == 2, "picked version never sent: \(req.calls)")

            let magnet = MagnetAddModel(target: .init(contentKey: "movie:1", tmdbID: 1, title: "M",
                                                      kind: .movie), downloads: store)
            magnet.update(text: "magnet:?xt=urn:btih:" + String(repeating: "c", count: 40))
            await magnet.submit()
            #expect(magnet.state != .submitted || req.calls.contains(String(repeating: "c", count: 40)),
                    "magnet reported submitted but never added: state=\(magnet.state) calls=\(req.calls)")
        }

        // F2 — Mark Season Watched on one show crowds every other show's Up Next off Home.
        @MainActor @Test func aBulkMarkDoesNotCrowdOtherShowsOffHome() async throws {
            let p = try provider()
            let y = show(2, seasons: [1: 3]), x = show(1, seasons: [1: 30])
            try await p.record(contentKey: "show:tmdb:2:s1e1", sourceKey: "y", positionSeconds: 1300,
                               durationSeconds: 1320, finished: true, profileID: "p1")
            let home = HomeStore(watch: p); home.activeProfileID = "p1"
            await home.rebuild(movies: [], shows: [y, x])
            #expect(home.continueWatching.map(\.contentKey) == ["show:tmdb:2:s1e2"])   // baseline
            let detail = DetailStore(item: x, details: ListsSeason(), watch: p, profileID: "p1")
            await detail.setSeasonWatched(true, season: 1)
            await home.rebuild(movies: [], shows: [y, x])
            #expect(home.continueWatching.map(\.contentKey).contains("show:tmdb:2:s1e2"),
                    "Y's Up Next vanished after marking X's season: \(home.continueWatching.map(\.contentKey))")
        }

        // F3 — "Mark Episode Unwatched" on a show's card resets THAT episode; the show is still being
        // watched, so it stays on the rail with the episode up next from the start. (The menu's own
        // copy used to promise that both marks take the card off — true for films, not for shows,
        // whose way off the rail is "Mark Show Unwatched".)
        @MainActor @Test func unmarkingAShowsEpisodeLeavesItUpNextFromTheStart() async throws {
            let p = try provider()
            let s = show(1, seasons: [1: 3])
            try await p.record(contentKey: "show:tmdb:1:s1e1", sourceKey: "a", positionSeconds: 1300,
                               durationSeconds: 1320, finished: true, profileID: "p1")
            try await p.record(contentKey: "show:tmdb:1:s1e2", sourceKey: "b", positionSeconds: 600,
                               durationSeconds: 1320, finished: false, profileID: "p1")
            let home = HomeStore(watch: p); home.activeProfileID = "p1"
            await home.rebuild(movies: [], shows: [s])
            let card = try #require(home.continueWatching.first)
            #expect(card.contentKey == "show:tmdb:1:s1e2" && !card.isUpNext)
            await home.setWatched(false, entry: card)
            await home.rebuild(movies: [], shows: [s])   // ContinueWatchingActions.refresh
            let after = try #require(home.continueWatching.first)
            #expect(after.contentKey == "show:tmdb:1:s1e2" && after.isUpNext && after.resumeAt == nil,
                    "\(home.continueWatching.map { ($0.contentKey, $0.isUpNext, $0.resumeAt) })")
        }

        // F4 — marking an EARLIER season watched hijacks Play (title page) and Home's card.
        @MainActor @Test func markingEarlierSeasonsDoesNotSendPlayBack() async throws {
            let p = try provider()
            let s = show(1, seasons: [1: 3, 2: 3, 3: 3])
            try await p.record(contentKey: "show:tmdb:1:s3e1", sourceKey: "a", positionSeconds: 1300,
                               durationSeconds: 1320, finished: true, profileID: "p1")
            try await p.record(contentKey: "show:tmdb:1:s3e2", sourceKey: "b", positionSeconds: 600,
                               durationSeconds: 1320, finished: false, profileID: "p1")
            let store = DetailStore(item: s, details: ListsSeason(), watch: p, profileID: "p1")
            await store.load()
            #expect(store.nextEpisode()?.id == "s3e2")          // baseline: resume S3E2
            await store.setSeasonWatched(true, season: 1)
            await store.setSeasonWatched(true, season: 2)
            await store.reloadWatch()
            #expect(store.nextEpisode()?.id == "s3e2",
                    "Play now targets \(store.nextEpisode()?.id ?? "nil")")
            let home = HomeStore(watch: p); home.activeProfileID = "p1"
            await home.rebuild(movies: [], shows: [s])
            #expect(home.continueWatching.map(\.contentKey) == ["show:tmdb:1:s3e2"],
                    "Home card: \(home.continueWatching.map { ($0.contentKey, $0.isUpNext) })")
        }

        // F5 — caught up on an airing season: Play targets an episode TMDB lists but has not aired.
        @MainActor @Test func playNeverTargetsAnEpisodeThatHasNotAired() async throws {
            let p = try provider()
            let s = show(1, seasons: [1: 2])
            try await p.record(contentKey: "show:tmdb:1:s1e2", sourceKey: "a", positionSeconds: 1300,
                               durationSeconds: 1320, finished: true, profileID: "p1")
            let eps = (1...3).map { n in
                TMDBEpisodeDetails(episodeNumber: n, name: "E\(n)", overview: nil, stillPath: nil,
                                   runtime: 22, airDate: n == 3 ? "2099-01-01" : "2026-09-01")
            }
            let store = DetailStore(item: s, details: ListsSeason(episodes: eps), watch: p, profileID: "p1")
            await store.load()
            await store.selectSeason(1)
            let target = store.nextEpisodeTarget()
            #expect(!(target?.season == 1 && target?.number == 3),
                    "Play targets unaired S1E3 (owned=\(store.nextEpisode()?.id ?? "nil"))")
        }
    }
}

private struct SlowTV: MediaDetailsProviding {
    var seasons: Int
    var perSeason: [Int: Int]
    var delayMS: Int = 0
    func movieDetails(tmdbID: Int) async throws -> TMDBMovieDetails { throw Boom.nope }
    func tvDetails(tmdbID: Int) async throws -> TMDBTVDetails {
        if delayMS > 0 { try await Task.sleep(for: .milliseconds(delayMS)) }
        return TMDBTVDetails(id: tmdbID, name: "S", firstAirDate: nil, overview: nil, posterPath: nil,
                             backdropPath: nil, numberOfSeasons: seasons, genres: [], voteAverage: nil)
    }
    func seasonEpisodes(tvID: Int, season: Int) async throws -> [TMDBEpisodeDetails] {
        (0..<(perSeason[season] ?? 0)).map { i in
            TMDBEpisodeDetails(episodeNumber: i + 1, name: nil, overview: nil, stillPath: nil,
                               runtime: 22, airDate: nil)
        }
    }
}

extension SwiftDataSuite {
    @Suite struct ReviewRegressionTests2 {
        private func provider() throws -> LocalWatchProvider {
            let c = try ModelContainer(for: WatchProgress.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            return LocalWatchProvider(store: LocalWatchStore(modelContainer: c), profileID: { "p1" })
        }

        // F5b — finished the finale of a renewed show: the page opens on the empty next season.
        @MainActor @Test func aRenewedShowDoesNotOpenOnItsEmptyNewSeason() async throws {
            let p = try provider()
            let s = show(1, seasons: [1: 3])
            try await p.record(contentKey: "show:tmdb:1:s1e3", sourceKey: "a", positionSeconds: 1300,
                               durationSeconds: 1320, finished: true, profileID: "p1")
            let store = DetailStore(item: s, details: SlowTV(seasons: 2, perSeason: [1: 3]), watch: p,
                                    profileID: "p1")
            await store.load()
            #expect(store.selectedSeason == 1,
                    "opened on season \(store.selectedSeason), state=\(store.episodesState(forSeason: store.selectedSeason)) target=\(String(describing: store.nextEpisodeTarget()))")
        }

        // F6 — a season chosen while the page loads is taken back when the load finishes.
        @MainActor @Test func aSeasonPickedWhileThePageLoadsIsKept() async throws {
            let p = try provider()
            let s = show(1, seasons: [1: 3, 2: 3, 3: 3])
            try await p.record(contentKey: "show:tmdb:1:s3e2", sourceKey: "a", positionSeconds: 600,
                               durationSeconds: 1320, finished: false, profileID: "p1")
            let store = DetailStore(item: s, details: SlowTV(seasons: 3, perSeason: [1: 3, 2: 3, 3: 3],
                                                             delayMS: 300),
                                    watch: p, profileID: "p1")
            async let loading: Void = store.load()
            try await Task.sleep(for: .milliseconds(50))
            await store.selectSeason(2)                         // the viewer picks Season 2
            await loading
            #expect(store.selectedSeason == 2, "load moved the viewer to season \(store.selectedSeason)")
        }

        // F7 — a GAP in the episodes you own (E1–E3 and E5, E3 finished): Home offers the next OWNED
        // episode (E5), the title page the next LISTED one (E4, which it fetches). Both are defensible
        // and which one Seret means is the owner's call, so this is recorded rather than "fixed".
        // (Mac poster Play no longer reports "couldn't play" for it: it opens the title page.)
        @MainActor @Test func aGapInOwnedEpisodesIsAKnownDisagreement() async throws {
            let p = try provider()
            let s = MediaItem(id: "show:tmdb:1", kind: .show, title: "S", year: 2020, sources: [],
                              seasons: [Season(number: 1, episodes: [1, 2, 3, 5].map { n in
                                  Episode(season: 1, number: n, source: src("g\(n)")) })], tmdbID: 1)
            try await p.record(contentKey: "show:tmdb:1:s1e3", sourceKey: "a", positionSeconds: 1300,
                               durationSeconds: 1320, finished: true, profileID: "p1")
            let store = DetailStore(item: s, details: ListsSeason(), watch: p, profileID: "p1")
            await store.loadPreferredVersion()          // exactly QuickPlay.request's sequence
            await store.reloadWatch()
            let home = HomeStore(watch: p); home.activeProfileID = "p1"
            await home.rebuild(movies: [], shows: [s])
            let homeKey = home.continueWatching.first?.contentKey
            let page = store.nextEpisodeTarget()
            withKnownIssue("Home offers the next owned episode, the page the next listed one") {
                #expect(homeKey == page.map { "show:tmdb:1:s\($0.season)e\($0.number)" },
                        "Home says \(homeKey ?? "nil"), page says \(String(describing: page))")
            }
        }
    }
}

/// `seasons` seasons of `perSeason` episodes each; in the LAST season, episodes from `unairedFrom`
/// on air in 2099.
private struct AiringTV: MediaDetailsProviding {
    var seasons: Int
    var perSeason: Int
    var unairedFrom: Int
    func movieDetails(tmdbID: Int) async throws -> TMDBMovieDetails { throw Boom.nope }
    func tvDetails(tmdbID: Int) async throws -> TMDBTVDetails {
        TMDBTVDetails(id: tmdbID, name: "S", firstAirDate: nil, overview: nil, posterPath: nil,
                      backdropPath: nil, numberOfSeasons: seasons, genres: [], voteAverage: nil)
    }
    func seasonEpisodes(tvID: Int, season: Int) async throws -> [TMDBEpisodeDetails] {
        (1...perSeason).map { k in
            TMDBEpisodeDetails(episodeNumber: k, name: "E\(k)", overview: nil, stillPath: nil, runtime: 22,
                               airDate: season == seasons && k >= unairedFrom ? "2099-01-01" : "2020-01-01")
        }
    }
}

/// A show's details fail `failures` times, then answer: three seasons of three aired episodes.
private final class FlakyTV: MediaDetailsProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var failuresLeft: Int
    init(failures: Int) { failuresLeft = failures }
    func movieDetails(tmdbID: Int) async throws -> TMDBMovieDetails { throw Boom.nope }
    func tvDetails(tmdbID: Int) async throws -> TMDBTVDetails {
        let fail = lock.withLock { () -> Bool in
            guard failuresLeft > 0 else { return false }
            failuresLeft -= 1
            return true
        }
        if fail { throw Boom.nope }
        return TMDBTVDetails(id: tmdbID, name: "S", firstAirDate: nil, overview: nil, posterPath: nil,
                             backdropPath: nil, numberOfSeasons: 3, genres: [], voteAverage: nil)
    }
    func seasonEpisodes(tvID: Int, season: Int) async throws -> [TMDBEpisodeDetails] {
        (1...3).map { k in
            TMDBEpisodeDetails(episodeNumber: k, name: "E\(k)", overview: nil, stillPath: nil, runtime: 22,
                               airDate: "2020-01-01")
        }
    }
}

extension SwiftDataSuite {
    /// Round 2 of the review: caught up on a show still airing; a Try Again that kept the season.
    @Suite struct CaughtUpTests {
        private func provider() throws -> LocalWatchProvider {
            let c = try ModelContainer(for: WatchProgress.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            return LocalWatchProvider(store: LocalWatchStore(modelContainer: c), profileID: { "p1" })
        }

        private func finish(_ keys: [String], in p: LocalWatchProvider) async throws {
            for key in keys {
                try await p.record(contentKey: key, sourceKey: "a", positionSeconds: 1300,
                                   durationSeconds: 1320, finished: true, profileID: "p1")
                try await Task.sleep(for: .milliseconds(5))     // distinct timestamps, in order
            }
        }

        /// Owned S1E1–S2E2, every one watched; TMDB lists S2E3 for next week. The page opened on
        /// SEASON 1 offering "Play S1·E1" — the answer for a series that has run out — a season
        /// away from where the viewer is and from the date the next one airs.
        @MainActor @Test func caughtUpOnAnOwnedShowStaysWhereTheViewerIs() async throws {
            let p = try provider()
            try await finish(["show:tmdb:1:s1e1", "show:tmdb:1:s1e2", "show:tmdb:1:s2e1",
                              "show:tmdb:1:s2e2"], in: p)
            let store = DetailStore(item: show(1, seasons: [1: 2, 2: 2]),
                                    details: AiringTV(seasons: 2, perSeason: 3, unairedFrom: 3),
                                    watch: p, profileID: "p1")
            await store.load()

            #expect(store.selectedSeason == 2)
            #expect(store.nextEpisode()?.id == "s2e2")
            let target = store.nextEpisodeTarget()
            #expect(target?.season == 2 && target?.number == 2, "Play targets \(String(describing: target))")
        }

        /// …and a show you do not own (watched, files gone): Play fell through to the season's
        /// first unwatched ROW — next week's S1E3, which no indexer has.
        @MainActor @Test func caughtUpOnAShowYouDoNotOwnNeverTargetsTheUnairedOne() async throws {
            let p = try provider()
            try await finish(["show:tmdb:1:s1e1", "show:tmdb:1:s1e2"], in: p)
            let store = DetailStore(item: MediaItem(id: "show:tmdb:1", kind: .show, title: "S", year: 2020,
                                                    sources: [], seasons: [], tmdbID: 1),
                                    details: AiringTV(seasons: 1, perSeason: 3, unairedFrom: 3),
                                    watch: p, profileID: "p1")
            await store.load()

            let target = store.nextEpisodeTarget()
            #expect(target?.season == 1 && target?.number == 2, "Play targets \(String(describing: target))")
        }

        /// A show that has not premiered has nothing Play can start — rather than a Play for an
        /// episode no indexer can have yet.
        @MainActor @Test func aShowThatHasNotPremieredOffersNoEpisodeToPlay() async throws {
            let p = try provider()
            let store = DetailStore(item: MediaItem(id: "show:tmdb:1", kind: .show, title: "S", year: 2020,
                                                    sources: [], seasons: [], tmdbID: 1),
                                    details: AiringTV(seasons: 1, perSeason: 3, unairedFrom: 1),
                                    watch: p, profileID: "p1")
            await store.load()

            #expect(store.nextEpisodeTarget() == nil)
            // …and says when it arrives, so the Apple TV page has something to hold its focus.
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = TimeZone(identifier: "UTC")!
            #expect(store.nextAirDate == utc.date(from: DateComponents(year: 2099, month: 1, day: 1)))
        }

        /// The page's details failed; the viewer picked season 3, then pressed Try Again. The reload
        /// worked out where they are in the show (part-way through S2E2) and moved them there — off
        /// the season they had just chosen. Only a pick made DURING a load counted.
        @MainActor @Test func aSeasonPickedBeforeTryAgainIsKept() async throws {
            let p = try provider()
            try await p.record(contentKey: "show:tmdb:1:s2e2", sourceKey: "a", positionSeconds: 600,
                               durationSeconds: 1320, finished: false, profileID: "p1")
            let store = DetailStore(item: show(1, seasons: [1: 3, 2: 3, 3: 3]), details: FlakyTV(failures: 1),
                                    watch: p, profileID: "p1")
            await store.load()
            #expect(store.richState == .failed)

            await store.selectSeason(3)
            await store.retrySeason()

            #expect(store.richState == .loaded)
            #expect(store.selectedSeason == 3, "Try Again moved the viewer to season \(store.selectedSeason)")
        }

        /// …while a Try Again nobody steered still opens where the viewer is.
        @MainActor @Test func tryAgainWithoutAPickStillOpensWhereTheViewerIs() async throws {
            let p = try provider()
            try await p.record(contentKey: "show:tmdb:1:s2e2", sourceKey: "a", positionSeconds: 600,
                               durationSeconds: 1320, finished: false, profileID: "p1")
            let store = DetailStore(item: show(1, seasons: [1: 3, 2: 3, 3: 3]), details: FlakyTV(failures: 1),
                                    watch: p, profileID: "p1")
            await store.load()
            await store.retrySeason()

            #expect(store.richState == .loaded)
            #expect(store.selectedSeason == 2)
        }

        /// The series that HAS run out still starts over from the top.
        @MainActor @Test func aFinishedSeriesStillStartsOverFromTheTop() async throws {
            let p = try provider()
            try await finish(["show:tmdb:1:s1e1", "show:tmdb:1:s1e2", "show:tmdb:1:s2e1",
                              "show:tmdb:1:s2e2"], in: p)
            let store = DetailStore(item: show(1, seasons: [1: 2, 2: 2]),
                                    details: AiringTV(seasons: 2, perSeason: 2, unairedFrom: 99),
                                    watch: p, profileID: "p1")
            await store.load()

            #expect(store.nextEpisode()?.id == "s1e1")
        }
    }
}
