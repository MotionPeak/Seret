import Testing
import Foundation
import DebridCore
@testable import DebridUI

@MainActor
@Suite struct AddStoreHebrewTests {
    private final class Source: StreamSource {
        let found: [CachedStream]
        init(_ found: [CachedStream]) { self.found = found }
        func streams(for query: StreamQuery) async throws -> [CachedStream] { found }
    }

    private final class NoAdd: AddProviding {
        func add(infoHash: String) async throws -> TorrentInfo { throw CancellationError() }
    }

    private static func stream(_ hash: String, _ name: String, subs: [String] = []) -> CachedStream {
        CachedStream(infoHash: hash, fileIdx: nil, rawTitle: name, parsed: FilenameParser().parse(name),
                     languages: [], sizeBytes: nil, sourceName: nil, isCached: true, subtitleLanguages: subs)
    }

    private let uhd = Self.stream("a", "Oppenheimer.2023.2160p.WEB-DL.x265-FLUX")
    private let tagged720 = Self.stream("b", "Oppenheimer.2023.720p.BluRay.x264.HebSubs", subs: ["he"])
    private let sparks = Self.stream("c", "Oppenheimer.2023.1080p.BluRay.x264-SPARKS")
    private let sparksHebrew = SubtitleResult(fileID: 1, language: "he",
                                              release: "Oppenheimer.2023.1080p.BluRay.x264-SPARKS")

    private func store(_ streams: [CachedStream], evidence: FakeSubtitleEvidence?,
                       wait: Duration = .seconds(3)) -> AddStore {
        AddStore(imdbID: "tt15398776", kind: .movie, originalLanguage: "en",
                 streamSource: Source(streams), add: NoAdd(), title: "Oppenheimer", year: 2023,
                 subtitleEvidence: evidence,
                 subtitleTarget: .movie(tmdbID: 872585, title: "Oppenheimer", year: 2023),
                 hebrewWait: wait)
    }

    /// The wait is the store's, paid once. The movie Versions screen ranks twice — the cached list
    /// on open, then the full list — and a slow search cost the full wait each time.
    @Test func theHebrewWaitIsPaidOncePerStore() async {
        let gate = HebrewGate()
        let s = store([uhd, sparks], evidence: FakeSubtitleEvidence(results: [sparksHebrew], gate: gate),
                      wait: .seconds(2))
        await s.loadStreams()                      // pays the wait: the search is held open
        let clock = ContinuousClock()
        let started = clock.now
        await s.loadAllVersions()
        #expect(clock.now - started < .seconds(1))
        await gate.release()
    }

    /// With nothing to put in order there is nothing to wait for.
    @Test func aSingleVersionIsNotHeldForTheSearch() async {
        let gate = HebrewGate()
        let s = store([uhd], evidence: FakeSubtitleEvidence(results: [], gate: gate), wait: .seconds(2))
        let clock = ContinuousClock()
        let started = clock.now
        await s.loadStreams()
        #expect(clock.now - started < .seconds(1))
        #expect(s.best?.infoHash == "a")
        await gate.release()
    }

    @Test func getBestTakesTheHebrewVersionEvenAt720p() async {
        let s = store([uhd, tagged720], evidence: FakeSubtitleEvidence(results: []))
        await s.loadStreams()
        #expect(s.best?.infoHash == "b")
        #expect(s.ranked.map(\.infoHash) == ["b", "a"])
        #expect(s.hebrew(for: tagged720) == .builtIn)
    }

    @Test func aMatchedReleaseRanksAboveUnmatched() async {
        let s = store([uhd, sparks], evidence: FakeSubtitleEvidence(results: [sparksHebrew]))
        await s.loadAllVersions()
        #expect(s.allVersions.map(\.infoHash) == ["c", "a"])
        #expect(s.hebrew(for: sparks) == .matched)
    }

    @Test func aSlowSearchDoesNotHoldTheListAndLateResultsOnlyAddBadges() async {
        let gate = HebrewGate()
        let s = store([uhd, sparks], evidence: FakeSubtitleEvidence(results: [sparksHebrew], gate: gate),
                      wait: .milliseconds(50))
        await s.loadAllVersions()
        #expect(s.allVersions.map(\.infoHash) == ["a", "c"])   // the search missed the deadline
        #expect(s.hebrew(for: sparks) == .none)
        await gate.release()
        #expect(await hebrewEventually { s.hebrew(for: sparks) == .matched })
        #expect(s.allVersions.map(\.infoHash) == ["a", "c"])   // …and nothing moved under the viewer
    }

    @Test func theListAndGetBestShareOneSearch() async {
        let evidence = FakeSubtitleEvidence(results: [sparksHebrew])
        let s = store([uhd, sparks], evidence: evidence)
        await s.loadStreams()
        await s.loadAllVersions()
        #expect(evidence.searchKeys == ["movie:tmdb:872585"])
    }

    @Test func withoutEvidenceTheOrderIsTodays() async {
        let s = AddStore(imdbID: "tt1", kind: .movie, originalLanguage: "en",
                         streamSource: Source([uhd, sparks]), add: NoAdd())
        await s.loadAllVersions()
        #expect(s.allVersions.map(\.infoHash) == ["a", "c"])
    }

    @Test func anEpisodeTargetAsksAboutThatEpisode() {
        let target = SubtitleTarget.forKind(.series(season: 1, episode: 3), tmdbID: 1396,
                                            title: "Breaking Bad", year: 2008)
        #expect(target.contentKey == "show:tmdb:1396:s1e3")
        #expect(target.query.season == 1)
        #expect(target.query.episode == 3)
        #expect(SubtitleTarget.forKind(.movie, tmdbID: 7, title: "M", year: nil).contentKey == "movie:tmdb:7")
    }
}
