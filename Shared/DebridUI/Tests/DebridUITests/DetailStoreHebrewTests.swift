import Testing
import Foundation
import DebridCore
@testable import DebridUI

@MainActor
@Suite struct DetailStoreHebrewTests {
    private struct Details: MediaDetailsProviding {
        var language: String? = "en"
        func movieDetails(tmdbID: Int) async throws -> TMDBMovieDetails {
            TMDBMovieDetails(id: tmdbID, title: "Oppenheimer", releaseDate: "2023-07-19", overview: nil,
                             posterPath: nil, backdropPath: nil, runtime: 180, genres: [],
                             voteAverage: nil, originalLanguage: language, imdbID: "tt15398776")
        }
        func tvDetails(tmdbID: Int) async throws -> TMDBTVDetails { throw CancellationError() }
        func seasonEpisodes(tvID: Int, season: Int) async throws -> [TMDBEpisodeDetails] { [] }
    }

    private final class Prefs: VersionPreferring, @unchecked Sendable {
        var stored: [String: String] = [:]
        func preferred(forContentKey key: String) async -> String? { stored[key] }
        func choose(contentKey: String, sourceKey: String) async { stored[contentKey] = sourceKey }
        func clear(contentKey: String) async { stored[contentKey] = nil }
    }

    private func movie(_ sources: [MediaSource]) -> MediaItem {
        MediaItem(id: "movie:tmdb:872585", kind: .movie, title: "Oppenheimer", year: 2023,
                  sources: sources, seasons: [], tmdbID: 872585)
    }

    private let uhd = MediaSource(torrentID: "A", fileID: 1, restrictedLink: "rd://A",
                                  parsed: FilenameParser().parse("Oppenheimer.2023.2160p.WEB-DL.x265-FLUX.mkv"))
    private let hd = MediaSource(torrentID: "B", fileID: 1, restrictedLink: "rd://B",
                                 parsed: FilenameParser().parse("Oppenheimer.2023.1080p.BluRay.x264-SPARKS.mkv"))
    private let hebrewText = ContainerTrack(kind: .subtitle, language: "he", codec: "S_TEXT/UTF8")
    private let sparks = SubtitleResult(fileID: 1, language: "he",
                                        release: "Oppenheimer.2023.1080p.BluRay.x264-SPARKS")

    @Test func aCopyWithHebrewBuiltInBecomesWhatPlayPlays() async {
        let evidence = FakeSubtitleEvidence(results: [], records: [
            WatchKey.source(hd): VersionSubtitleRecord(origin: .header, tracks: [hebrewText])])
        let store = DetailStore(item: movie([uhd, hd]), details: Details(), watch: nil,
                                subtitleEvidence: evidence)
        #expect(store.bestSource == uhd)            // before any evidence: today's ranking
        await store.load()
        #expect(store.bestSource == hd)
        #expect(store.versions == [hd, uhd])
        #expect(store.hebrewChip == .builtIn)
        #expect(store.hebrew(for: hd) == .builtIn)
        #expect(store.hebrew(for: uhd) == .none)
    }

    /// A revisit's Play must play the Hebrew copy at once, however slow OpenSubtitles is today:
    /// what earlier visits stored is published before anything touches the network.
    @Test func whatAnEarlierVisitStoredShowsBeforeTheSearchAnswers() async {
        let gate = HebrewGate()
        let record = VersionSubtitleRecord(origin: .header, tracks: [hebrewText])
        let stored = SubtitleEvidenceSet(byVersion: [WatchKey.source(hd): SubtitleEvidence(hebrew: .builtIn)],
                                         originalLanguage: "en")
        let evidence = FakeSubtitleEvidence(results: [], records: [WatchKey.source(hd): record],
                                            stored: stored, gate: gate)
        let store = DetailStore(item: movie([uhd, hd]), details: Details(), watch: nil,
                                subtitleEvidence: evidence)
        let loading = Task { await store.load() }
        #expect(await hebrewEventually { store.bestSource == hd })
        #expect(store.hebrewChip == .builtIn)
        await gate.release()
        await loading.value
        #expect(store.bestSource == hd)
    }

    @Test func aSubtitleMadeForACopyIsMatched() async {
        let store = DetailStore(item: movie([uhd, hd]), details: Details(), watch: nil,
                                subtitleEvidence: FakeSubtitleEvidence(results: [sparks]))
        await store.load()
        #expect(store.bestSource == hd)
        #expect(store.hebrewChip == .matched)
    }

    @Test func hebrewThatExistsButNotForThisCopyIsAvailable() async {
        let store = DetailStore(item: movie([uhd]), details: Details(), watch: nil,
                                subtitleEvidence: FakeSubtitleEvidence(results: [sparks]))
        await store.load()
        #expect(store.hebrewChip == .available)
    }

    @Test func nothingKnownShowsNoChip() async {
        let store = DetailStore(item: movie([uhd, hd]), details: Details(), watch: nil,
                                subtitleEvidence: FakeSubtitleEvidence(results: []))
        await store.load()
        #expect(store.hebrewChip == nil)
        #expect(store.bestSource == uhd)
    }

    @Test func aChosenCopyStillWins() async {
        let prefs = Prefs()
        prefs.stored["movie:tmdb:872585"] = WatchKey.source(uhd)
        let evidence = FakeSubtitleEvidence(results: [], records: [
            WatchKey.source(hd): VersionSubtitleRecord(origin: .header, tracks: [hebrewText])])
        let store = DetailStore(item: movie([uhd, hd]), details: Details(), watch: nil,
                                versionPrefs: prefs, subtitleEvidence: evidence)
        await store.loadPreferredVersion()
        await store.load()
        #expect(store.bestSource == uhd)
    }

    @Test func aFilmYouDoNotOwnShowsAvailable() async {
        let store = DetailStore(item: movie([]), details: Details(), watch: nil,
                                subtitleEvidence: FakeSubtitleEvidence(results: [sparks]))
        await store.load()
        #expect(store.hebrewChip == .available)
    }

    @Test func aFilmInHebrewGetsNoBoost() async {
        let evidence = FakeSubtitleEvidence(results: [], records: [
            WatchKey.source(hd): VersionSubtitleRecord(origin: .header, tracks: [hebrewText])])
        let store = DetailStore(item: movie([uhd, hd]), details: Details(language: "he"), watch: nil,
                                subtitleEvidence: evidence)
        await store.load()
        #expect(store.bestSource == uhd)
    }

    @Test func theSearchIsForThisFilm() async {
        let evidence = FakeSubtitleEvidence(results: [])
        let store = DetailStore(item: movie([hd]), details: Details(), watch: nil, subtitleEvidence: evidence)
        await store.load()
        #expect(evidence.searchKeys == ["movie:tmdb:872585"])
    }

    @Test func theLanguageIsNamed() async {
        let korean = DetailStore(item: movie([]), details: Details(language: "ko"), watch: nil)
        await korean.load()
        #expect(korean.languageName == "Korean")
        let silent = DetailStore(item: movie([]), details: Details(language: "xx"), watch: nil)
        await silent.load()
        #expect(silent.languageName == nil)
    }
}
