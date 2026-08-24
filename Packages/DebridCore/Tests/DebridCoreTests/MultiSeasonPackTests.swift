import Testing
@testable import DebridCore

/// A complete-series pack must land under the show it belongs to.
///
/// Spotted on the real Apple TV: a tile reading "Sherlock S01-S04 + Extras Complete" sitting next
/// to Sherlock, with no poster. `extractTitle` splits on `.`, `_` and space but NOT `-`, so
/// `S01-S04` stays one token and the stop pattern `^s\d{1,2}$` never matches it. The title then
/// runs on through the rest of the name, and since shows are grouped by title key the pack becomes
/// its own separate "show" — TMDB cannot match it (hence no poster), and every episode inside it is
/// stranded there instead of appearing under Sherlock.
struct MultiSeasonPackTests {
    let parser = FilenameParser()
    let builder = LibraryBuilder()

    @Test func aSeasonRangeEndsTheTitle() {
        #expect(parser.parse("Sherlock.S01-S04.+.Extras.Complete.1080p.BluRay.x265").title == "Sherlock")
    }

    @Test func seasonRangeFormsAllEndTheTitle() {
        for name in ["Show.S01-S04.1080p", "Show.S1-S4.1080p", "Show.S01-04.1080p",
                     "Show.S01-S10.COMPLETE.1080p"] {
            #expect(parser.parse(name).title == "Show", "for \(name)")
        }
    }

    /// The guard: a single-season pack and a normal episode must be unaffected.
    @Test func ordinarySeasonAndEpisodeNamesAreUnchanged() {
        #expect(parser.parse("Sherlock.S01.1080p.BluRay.x265").title == "Sherlock")
        #expect(parser.parse("Sherlock.S01E03.1080p.BluRay.x265").title == "Sherlock")
        #expect(parser.parse("Sherlock.2010.1080p.BluRay.x265").title == "Sherlock")
    }

    /// A hyphen that is NOT a season range must still be part of the title — release names use
    /// hyphens in real titles.
    @Test func aHyphenatedTitleWordSurvives() {
        #expect(parser.parse("Spider-Man.2002.1080p.BluRay.x264").title == "Spider-Man")
    }

    /// End to end: the pack merges into the show, and its episodes are reachable there.
    @Test func aCompletePackMergesIntoTheShowAndItsEpisodesAreReachable() {
        let pack = TorrentInfo(
            id: "PACK", filename: "Sherlock.S01-S04.+.Extras.Complete.1080p.BluRay.x265",
            hash: "h", bytes: 9000, progress: 100, status: "downloaded",
            files: [
                TorrentFile(id: 1, path: "/Sherlock/Sherlock.S01E01.1080p.mkv", bytes: 2000, selected: 1),
                TorrentFile(id: 2, path: "/Sherlock/Sherlock.S02E01.1080p.mkv", bytes: 2000, selected: 1),
                TorrentFile(id: 3, path: "/Sherlock/Sherlock.S04E03.1080p.mkv", bytes: 2000, selected: 1),
            ],
            links: ["https://rd/S01E01", "https://rd/S02E01", "https://rd/S04E03"])

        let lib = builder.group([pack])
        #expect(lib.count == 1)                       // ONE show, not a show plus a bogus one
        let show = lib[0]
        #expect(show.title == "Sherlock")
        // Each file keeps its OWN season, rather than all collapsing into the pack's.
        #expect(show.seasons.map(\.number) == [1, 2, 4])
        #expect(show.seasons.first { $0.number == 4 }?.episodes.first?.source.restrictedLink
                == "https://rd/S04E03")
    }

    /// And it merges with episodes of the same show that arrived separately.
    @Test func theyMergeWithSeparatelyAddedEpisodes() {
        let pack = TorrentInfo(
            id: "PACK", filename: "Sherlock.S01-S04.Complete.1080p", hash: "h", bytes: 2000,
            progress: 100, status: "downloaded",
            files: [TorrentFile(id: 1, path: "/S/Sherlock.S01E01.1080p.mkv", bytes: 2000, selected: 1)],
            links: ["https://rd/pack-S01E01"])
        let single = TorrentInfo(
            id: "ONE", filename: "Sherlock.S02E02.2160p.WEB-DL", hash: "h2", bytes: 2000,
            progress: 100, status: "downloaded",
            files: [TorrentFile(id: 1, path: "/S/Sherlock.S02E02.2160p.mkv", bytes: 2000, selected: 1)],
            links: ["https://rd/single"])

        let lib = builder.group([pack, single])
        #expect(lib.count == 1)
        #expect(lib[0].seasons.map(\.number) == [1, 2])
    }
}
