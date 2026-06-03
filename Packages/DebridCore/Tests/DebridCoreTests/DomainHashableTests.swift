import Testing
import DebridCore

@Suite struct DomainHashableTests {
    private func ep(_ n: Int) -> Episode {
        Episode(season: 1, number: n,
                source: MediaSource(torrentID: "t", fileID: nil, restrictedLink: "l",
                                    parsed: ParsedRelease(title: "x")))
    }

    @Test func mediaItemUsableAsNavigationValue() {
        let s = MediaSource(torrentID: "t", fileID: 1, restrictedLink: "l",
                            parsed: ParsedRelease(title: "x", resolution: "1080p"))
        let a = MediaItem(id: "1", kind: .movie, title: "A", year: 2024, sources: [s], seasons: [])
        let b = MediaItem(id: "1", kind: .movie, title: "A", year: 2024, sources: [s], seasons: [])
        let c = MediaItem(id: "2", kind: .movie, title: "B", year: 2024, sources: [], seasons: [])
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)        // equal values hash equal
        var set: Set<MediaItem> = [a]
        #expect(set.contains(b))                   // separately-constructed equal value found
        set.insert(c)
        #expect(set.count == 2)                    // distinct value stays separate
    }

    @Test func episodeAndSeasonHashable() {
        // Separately-constructed equal values collapse in a Set; distinct values stay separate.
        #expect(Set([ep(1), ep(1)]).count == 1)
        #expect(Set([ep(1)]).contains(ep(1)))
        #expect(Set([ep(1), ep(2)]).count == 2)

        func season(_ episodes: [Episode]) -> Season { Season(number: 1, episodes: episodes) }
        #expect(Set([season([ep(1)]), season([ep(1)])]).count == 1)
        #expect(Set([season([ep(1)]), season([ep(2)])]).count == 2)
    }

    @Test func mediaKindAndParsedReleaseHashable() {
        #expect(Set([MediaKind.movie, .movie, .show]).count == 2)
        let p = ParsedRelease(title: "x", resolution: "1080p")
        let same = ParsedRelease(title: "x", resolution: "1080p")
        let diff = ParsedRelease(title: "x", resolution: "2160p")
        #expect(Set([p, same]).count == 1)
        #expect(Set([p, diff]).count == 2)
    }
}
