#if DEBUG
import DebridCore
import Foundation

/// Canned data every `-uiPreview` screen builds on: real TMDB poster/backdrop paths, fetched once
/// against the live API and hard-coded here so a screenshot shows real artwork with no network
/// call and no key at preview time. Reused by Tasks 4, 5 and 7.
enum Fixture {
    static func source(id: String, resolution: String = "2160p", videoCodec: String = "HEVC",
                       audioCodec: String = "DTS-HD", sizeBytes: Int = 8_000_000_000) -> MediaSource {
        MediaSource(torrentID: id, fileID: nil, restrictedLink: "https://real-debrid.invalid/\(id)",
                   parsed: ParsedRelease(title: id, resolution: resolution, source: "BluRay",
                                         videoCodec: videoCodec, audioCodec: audioCodec),
                   sizeBytes: sizeBytes)
    }

    private static func film(_ tmdbID: Int, _ title: String, _ year: Int,
                             _ poster: String, _ backdrop: String) -> MediaItem {
        MediaItem(id: "movie:tmdb:\(tmdbID)", kind: .movie, title: title, year: year,
                 sources: [source(id: "t\(tmdbID)")], seasons: [], tmdbID: tmdbID,
                 posterPath: poster, backdropPath: backdrop, overview: "A film about \(title).")
    }

    /// ~12 films — includes a long title ("The Lord of the Rings: The Fellowship of the Ring") to
    /// prove a card truncates rather than widening.
    static let films: [MediaItem] = [
        film(693134, "Dune: Part Two", 2024,
             "/6izwz7rsy95ARzTR3poZ8H6c5pp.jpg", "/eZ239CUp1d6OryZEBPnO2n87gMG.jpg"),
        film(120, "The Lord of the Rings: The Fellowship of the Ring", 2001,
             "/6oom5QYQ2yQTMJIbnvbkBL9cHo6.jpg", "/oiwc338EoBgS4sEI2ixAny4KQKg.jpg"),
        film(238, "The Godfather", 1972,
             "/3bhkrj58Vtu7enYsRolD1fZdja1.jpg", "/tSPT36ZKlP2WVHJLM4cQPLSzv3b.jpg"),
        film(27205, "Inception", 2010,
             "/xlaY2zyzMfkhk0HSC5VUwzoZPU1.jpg", "/8ZTVqvKDQ8emSGUEMjsS4yHAwrp.jpg"),
        film(157336, "Interstellar", 2014,
             "/yQvGrMoipbRoddT0ZR8tPoR7NfX.jpg", "/8sNiAPPYU14PUepFNeSNGUTiHW.jpg"),
        film(155, "The Dark Knight", 2008,
             "/qJ2tW6WMUDux911r6m7haRef0WH.jpg", "/9FE5eD92WfVCiivM9Pq9GVSrlWk.jpg"),
        film(496243, "Parasite", 2019,
             "/7IiTTgloJzvGI1TAYymCfbfl3vT.jpg", "/hiKmpZMGZsrkA3cdce8a7Dpos1j.jpg"),
        film(129, "Spirited Away", 2001,
             "/39wmItIWsg5sZMyRUHLkWBcuVCM.jpg", "/6oaL4DP75yABrd5EbC4H2zq5ghc.jpg"),
        film(603, "The Matrix", 1999,
             "/dXNAPwY7VrqMAo51EKhhCJfaGb5.jpg", "/lrtSb1skJayPydZk0OSMAKjBOVe.jpg"),
        film(680, "Pulp Fiction", 1994,
             "/vQWk5YBFWF4bZaofAbv0tShwBvQ.jpg", "/suaEOtk1N1sgg2MTM7oZd2cfVp3.jpg"),
        film(313369, "La La Land", 2016,
             "/uDO8zWDhfWwoFdKS4fzkUJt0Rf0.jpg", "/nlPCdZlHtRNcF6C9hzUH4ebmV1w.jpg"),
        film(872585, "Oppenheimer", 2023,
             "/8Gxv8gSFCU0XGDykEGv7zR1n2ua.jpg", "/neeNHeXjMF5fXoCJRsOmkNGC7q.jpg"),
    ]

    private static func episode(_ season: Int, _ number: Int, _ torrentID: String) -> Episode {
        Episode(season: season, number: number, source: source(id: torrentID))
    }

    /// "The" fixture show: a special, a fully-owned season, and a season only partly owned — what
    /// Task 5's season pills / episode grid need to prove Specials-last and "not downloaded".
    static let show: MediaItem = MediaItem(
        id: "show:tmdb:1396", kind: .show, title: "Breaking Bad", year: 2008,
        sources: [], seasons: [
            Season(number: 0, episodes: [episode(0, 1, "bb-s0e1")]),
            Season(number: 1, episodes: (1...6).map { episode(1, $0, "bb-s1e\($0)") }),
            Season(number: 2, episodes: (1...3).map { episode(2, $0, "bb-s2e\($0)") }),
        ],
        tmdbID: 1396, posterPath: "/anFx9aTOOYqgS3v7x3R84Kz67ly.jpg",
        backdropPath: "/tsRy63Mu5cu8etL1X7ZLyf7UP1M.jpg",
        overview: "A high school chemistry teacher turns to manufacturing after a cancer diagnosis.")

    private static func simpleShow(_ tmdbID: Int, _ title: String, _ year: Int,
                                   _ poster: String, _ backdrop: String) -> MediaItem {
        MediaItem(id: "show:tmdb:\(tmdbID)", kind: .show, title: title, year: year, sources: [],
                 seasons: [Season(number: 1, episodes: (1...6).map { episode(1, $0, "\(tmdbID)-s1e\($0)") })],
                 tmdbID: tmdbID, posterPath: poster, backdropPath: backdrop)
    }

    static let shows: [MediaItem] = [
        show,
        simpleShow(19885, "Sherlock", 2010,
                  "/7WTsnHkbA0FaG6R9twfFde0I9hl.jpg", "/8rvLEmdI4gLrMO1rLqbNdnNcPFE.jpg"),
        simpleShow(1399, "Game of Thrones", 2011,
                  "/1XS1oqL89opfnbLl8WnZY1O1uJx.jpg", "/zZqpAXxVSBtxV9qPBcscfXBcL2w.jpg"),
    ]

    /// Canned watch state: one finished film, one mid-watch film, and the fixture show's first
    /// three S1 episodes (two finished, one mid-watch) — what the poster/episode badges render.
    static let watch: [String: WatchState] = {
        var map: [String: WatchState] = [:]
        func set(_ key: String, source: MediaSource, position: Double, duration: Double, finished: Bool) {
            map[key] = WatchState(contentKey: key, sourceKey: WatchKey.source(source),
                                  positionSeconds: position, durationSeconds: duration,
                                  finished: finished, updatedAt: .now)
        }
        let godfather = films[2]
        set(WatchKey.content(forMovie: godfather), source: godfather.sources[0],
           position: 8150, duration: 8160, finished: true)

        let dune = films[0]
        set(WatchKey.content(forMovie: dune), source: dune.sources[0],
           position: 3753, duration: 8160, finished: false)

        let s1 = show.seasons.first { $0.number == 1 }!.episodes
        for ep in s1.prefix(2) {
            set(WatchKey.content(forShow: show, episode: ep), source: ep.source,
               position: 2570, duration: 2580, finished: true)
        }
        if let e3 = s1.first(where: { $0.number == 3 }) {
            set(WatchKey.content(forShow: show, episode: e3), source: e3.source,
               position: 1210, duration: 2580, finished: false)
        }
        return map
    }()
}
#endif
