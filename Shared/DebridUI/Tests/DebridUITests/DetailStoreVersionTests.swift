import Testing
import Foundation
import DebridCore
@testable import DebridUI

@MainActor
@Suite struct DetailStoreVersionTests {
    private final class FakePrefs: VersionPreferring, @unchecked Sendable {
        var stored: [String: String] = [:]
        func preferred(forContentKey key: String) async -> String? { stored[key] }
        func choose(contentKey: String, sourceKey: String) async { stored[contentKey] = sourceKey }
        func clear(contentKey: String) async { stored[contentKey] = nil }
    }

    private func source(_ torrentID: String, resolution: String) -> MediaSource {
        MediaSource(torrentID: torrentID, fileID: nil, restrictedLink: "l",
                    parsed: ParsedRelease(title: "T", resolution: resolution))
    }

    private func item(_ sources: [MediaSource]) -> MediaItem {
        MediaItem(id: "movie:tmdb:7", kind: .movie, title: "T", year: 2024,
                  sources: sources, seasons: [], tmdbID: 7)
    }

    private struct InertDetails: MediaDetailsProviding {
        func movieDetails(tmdbID: Int) async throws -> TMDBMovieDetails { throw CancellationError() }
        func tvDetails(tmdbID: Int) async throws -> TMDBTVDetails { throw CancellationError() }
        func seasonEpisodes(tvID: Int, season: Int) async throws -> [TMDBEpisodeDetails] { [] }
    }

    private func store(_ sources: [MediaSource], prefs: FakePrefs) -> DetailStore {
        DetailStore(item: item(sources), details: InertDetails(), watch: nil, versionPrefs: prefs)
    }

    @Test func withNoPreferenceTheRankerWins() async {
        let sd = source("A", resolution: "1080p"), hd = source("B", resolution: "2160p")
        let s = store([sd, hd], prefs: FakePrefs())
        await s.loadPreferredVersion()
        #expect(s.bestSource?.torrentID == "B")   // ranker prefers 2160p
    }

    @Test func aPreferenceOverridesTheRanker() async {
        let sd = source("A", resolution: "1080p"), hd = source("B", resolution: "2160p")
        let prefs = FakePrefs()
        prefs.stored["movie:tmdb:7"] = WatchKey.source(sd)
        let s = store([sd, hd], prefs: prefs)
        await s.loadPreferredVersion()
        #expect(s.bestSource?.torrentID == "A")
    }

    /// Delete that torrent from RD and Play must keep working, not break forever.
    @Test func aPreferenceForAVanishedSourceFallsBackToTheRanker() async {
        let hd = source("B", resolution: "2160p")
        let prefs = FakePrefs()
        prefs.stored["movie:tmdb:7"] = "GONE#-"
        let s = store([hd], prefs: prefs)
        await s.loadPreferredVersion()
        #expect(s.bestSource?.torrentID == "B")
    }

    @Test func choosingPersistsAndTakesEffect() async {
        let sd = source("A", resolution: "1080p"), hd = source("B", resolution: "2160p")
        let prefs = FakePrefs()
        let s = store([sd, hd], prefs: prefs)
        await s.chooseVersion(sd)
        #expect(prefs.stored["movie:tmdb:7"] == WatchKey.source(sd))
        #expect(s.bestSource?.torrentID == "A")
    }

    @Test func theActiveVersionIsIdentifiable() async {
        let sd = source("A", resolution: "1080p"), hd = source("B", resolution: "2160p")
        let s = store([sd, hd], prefs: FakePrefs())
        await s.loadPreferredVersion()
        #expect(s.isActive(hd))
        #expect(!s.isActive(sd))
    }

    @Test func clearingReturnsToTheRanker() async {
        let sd = source("A", resolution: "1080p"), hd = source("B", resolution: "2160p")
        let prefs = FakePrefs()
        let s = store([sd, hd], prefs: prefs)
        await s.chooseVersion(sd)
        await s.clearPreferredVersion()
        #expect(prefs.stored["movie:tmdb:7"] == nil)
        #expect(s.bestSource?.torrentID == "B")
    }

    /// `item` is a snapshot, so a deleted version has to disappear from this screen right away —
    /// otherwise its row stays listed and Play could still pick a torrent that no longer exists.
    @Test func aDeletedVersionLeavesTheListAndCantBePlayed() async {
        let sd = source("A", resolution: "1080p"), hd = source("B", resolution: "2160p")
        let s = store([sd, hd], prefs: FakePrefs())
        await s.loadPreferredVersion()
        await s.forgetVersion(hd)
        #expect(s.versions.map(\.torrentID) == ["A"])
        #expect(s.bestSource?.torrentID == "A")
    }

    /// Deleting the version you'd pinned must retire the pin too — a preference pointing at a
    /// torrent that no longer exists would follow the title around via CloudKit.
    @Test func deletingThePreferredVersionClearsThePreference() async {
        let sd = source("A", resolution: "1080p"), hd = source("B", resolution: "2160p")
        let prefs = FakePrefs()
        let s = store([sd, hd], prefs: prefs)
        await s.chooseVersion(sd)
        await s.forgetVersion(sd)
        #expect(prefs.stored["movie:tmdb:7"] == nil)
        #expect(s.preferredSourceKey == nil)
        #expect(s.bestSource?.torrentID == "B")
    }
}
