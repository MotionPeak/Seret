import Testing
import Foundation
import DebridCore
@testable import DebridUI

@MainActor
@Suite struct HomeStoreHebrewTests {
    private struct Watch: WatchProgressProviding {
        var states: [WatchState]
        func recentlyWatched(limit: Int, profileID: String) async throws -> [WatchState] { states }
        func progress(forContentKey key: String, profileID: String) async throws -> WatchState? { nil }
        func record(contentKey: String, sourceKey: String, positionSeconds: Double,
                    durationSeconds: Double, finished: Bool, profileID: String) async throws {}
        func deleteProgress(forContentKeys keys: [String]) async throws {}
    }

    private let uhd = MediaSource(torrentID: "A", fileID: 1, restrictedLink: "a",
                                  parsed: ParsedRelease(title: "T", resolution: "2160p"))
    private let hd = MediaSource(torrentID: "B", fileID: 1, restrictedLink: "b",
                                 parsed: ParsedRelease(title: "T", resolution: "1080p"))

    private func home(evidence: FakeSubtitleEvidence?) async -> HomeStore {
        let movie = MediaItem(id: "movie:tmdb:1", kind: .movie, title: "T", year: 2023,
                              sources: [uhd, hd], seasons: [], tmdbID: 1)
        let state = WatchState(contentKey: "movie:tmdb:1", sourceKey: WatchKey.source(uhd),
                               positionSeconds: 60, durationSeconds: 6000, finished: false, updatedAt: Date())
        let store = HomeStore(watch: Watch(states: [state]), subtitleEvidence: evidence)
        store.activeProfileID = "p"
        await store.rebuild(movies: [movie], shows: [])
        return store
    }

    @Test func resumePlaysTheCopyTheTitlePageWould() async {
        let stored = SubtitleEvidenceSet(byVersion: [WatchKey.source(hd): SubtitleEvidence(hebrew: .builtIn)],
                                         originalLanguage: "en")
        let store = await home(evidence: FakeSubtitleEvidence(stored: stored))
        #expect(store.continueWatching.first?.source == hd)
    }

    @Test func withoutEvidenceResumeIsUnchanged() async {
        let store = await home(evidence: nil)
        #expect(store.continueWatching.first?.source == uhd)
    }

    private struct Details: MediaDetailsProviding {
        let language: String
        func movieDetails(tmdbID: Int) async throws -> TMDBMovieDetails {
            TMDBMovieDetails(id: tmdbID, title: "T", releaseDate: "2023-01-01", overview: nil,
                             posterPath: nil, backdropPath: nil, runtime: 100, genres: [],
                             voteAverage: nil, originalLanguage: language, imdbID: "tt1")
        }
        func tvDetails(tmdbID: Int) async throws -> TMDBTVDetails { throw CancellationError() }
        func seasonEpisodes(tvID: Int, season: Int) async throws -> [TMDBEpisodeDetails] { [] }
    }

    /// The real service on both sides, and no OpenSubtitles key — as on a fresh install. An
    /// Israeli film's 1080p copy carries a Hebrew track: the title page, which knows the film's
    /// language from TMDB, keeps the 2160p. Home reads only what the title page stored, and had
    /// to reach the same answer.
    @Test func homeAndTheTitlePageAgreeWithNoSearch() async {
        let dir = FileManager.default.temporaryDirectory.appending(path: "home-agree-\(UUID().uuidString)")
        let hebrew = ContainerTrack(kind: .subtitle, language: "he", codec: "S_TEXT/UTF8")
        let service = SubtitleEvidenceService(
            directory: dir, search: nil,
            resolve: { link in ResolvedLink(url: URL(string: "https://cdn.example/\(link)")!, fileName: nil) },
            probe: { url in url.absoluteString.hasSuffix("/b") ? .tracks([hebrew]) : .tracks([]) })
        let movie = MediaItem(id: "movie:tmdb:1", kind: .movie, title: "T", year: 2023,
                              sources: [uhd, hd], seasons: [], tmdbID: 1)
        let page = DetailStore(item: movie, details: Details(language: "he"), watch: nil,
                               subtitleEvidence: service)
        await page.load()
        #expect(page.hebrew(for: hd) == .builtIn)          // the evidence is there…
        #expect(page.bestSource == uhd)                    // …and a Hebrew film takes no boost

        let state = WatchState(contentKey: "movie:tmdb:1", sourceKey: WatchKey.source(uhd),
                               positionSeconds: 60, durationSeconds: 6000, finished: false, updatedAt: Date())
        let home = HomeStore(watch: Watch(states: [state]), subtitleEvidence: service)
        home.activeProfileID = "p"
        await home.rebuild(movies: [movie], shows: [])
        #expect(home.continueWatching.first?.source == page.bestSource)
    }
}
