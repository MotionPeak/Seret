import Testing
@testable import DebridCore

@Suite struct StreamModelsTests {
    @Test func cachedStreamQualityRankUsesParsed() {
        let s = CachedStream(infoHash: "abc", fileIdx: 1, rawTitle: "Movie 2160p REMUX",
                             parsed: ParsedRelease(title: "Movie", resolution: "2160p", source: "REMUX"),
                             languages: ["en"], sizeBytes: 100, sourceName: "RD")
        #expect(s.qualityRank == releaseQualityRank(for: s.parsed))
        #expect(s.qualityRank > 0)
    }

    @Test func streamKindSeriesCarriesSeasonEpisode() {
        let q = StreamQuery(imdbID: "tt1", kind: .series(season: 2, episode: 5), originalLanguage: "en")
        if case let .series(season, episode) = q.kind {
            #expect(season == 2); #expect(episode == 5)
        } else { Issue.record("expected series") }
    }
}
