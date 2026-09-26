#if DEBUG
import DebridCore
import DebridUI
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

    /// A fixed anchor (not `.now`) so "Recently Added" order is stable across runs — a screenshot
    /// taken today and one taken next month must show the same ordering.
    private static let addedAtAnchor = Date(timeIntervalSinceReferenceDate: 780_000_000)
    /// `n` days before the anchor — every fixture film/show gets one of these, by its position
    /// below, so `HomeStore.recentlyAdded` (newest `addedAt` first) has a stable order.
    private static func daysAgo(_ n: Int) -> Date { addedAtAnchor.addingTimeInterval(-Double(n) * 86_400) }

    private static func film(_ tmdbID: Int, _ title: String, _ year: Int,
                             _ poster: String, _ backdrop: String, addedAt: Date) -> MediaItem {
        MediaItem(id: "movie:tmdb:\(tmdbID)", kind: .movie, title: title, year: year,
                 sources: [source(id: "t\(tmdbID)")], seasons: [], tmdbID: tmdbID,
                 posterPath: poster, backdropPath: backdrop, overview: "A film about \(title).",
                 addedAt: addedAt)
    }

    /// ~12 films — includes a long title ("The Lord of the Rings: The Fellowship of the Ring") to
    /// prove a card truncates rather than widening.
    static let films: [MediaItem] = [
        film(693134, "Dune: Part Two", 2024,
             "/6izwz7rsy95ARzTR3poZ8H6c5pp.jpg", "/eZ239CUp1d6OryZEBPnO2n87gMG.jpg", addedAt: daysAgo(0)),
        film(120, "The Lord of the Rings: The Fellowship of the Ring", 2001,
             "/6oom5QYQ2yQTMJIbnvbkBL9cHo6.jpg", "/oiwc338EoBgS4sEI2ixAny4KQKg.jpg", addedAt: daysAgo(1)),
        film(238, "The Godfather", 1972,
             "/3bhkrj58Vtu7enYsRolD1fZdja1.jpg", "/tSPT36ZKlP2WVHJLM4cQPLSzv3b.jpg", addedAt: daysAgo(2)),
        film(27205, "Inception", 2010,
             "/xlaY2zyzMfkhk0HSC5VUwzoZPU1.jpg", "/8ZTVqvKDQ8emSGUEMjsS4yHAwrp.jpg", addedAt: daysAgo(3)),
        film(157336, "Interstellar", 2014,
             "/yQvGrMoipbRoddT0ZR8tPoR7NfX.jpg", "/8sNiAPPYU14PUepFNeSNGUTiHW.jpg", addedAt: daysAgo(4)),
        film(155, "The Dark Knight", 2008,
             "/qJ2tW6WMUDux911r6m7haRef0WH.jpg", "/9FE5eD92WfVCiivM9Pq9GVSrlWk.jpg", addedAt: daysAgo(5)),
        film(496243, "Parasite", 2019,
             "/7IiTTgloJzvGI1TAYymCfbfl3vT.jpg", "/hiKmpZMGZsrkA3cdce8a7Dpos1j.jpg", addedAt: daysAgo(6)),
        film(129, "Spirited Away", 2001,
             "/39wmItIWsg5sZMyRUHLkWBcuVCM.jpg", "/6oaL4DP75yABrd5EbC4H2zq5ghc.jpg", addedAt: daysAgo(7)),
        film(603, "The Matrix", 1999,
             "/dXNAPwY7VrqMAo51EKhhCJfaGb5.jpg", "/lrtSb1skJayPydZk0OSMAKjBOVe.jpg", addedAt: daysAgo(8)),
        film(680, "Pulp Fiction", 1994,
             "/vQWk5YBFWF4bZaofAbv0tShwBvQ.jpg", "/suaEOtk1N1sgg2MTM7oZd2cfVp3.jpg", addedAt: daysAgo(9)),
        film(313369, "La La Land", 2016,
             "/uDO8zWDhfWwoFdKS4fzkUJt0Rf0.jpg", "/nlPCdZlHtRNcF6C9hzUH4ebmV1w.jpg", addedAt: daysAgo(10)),
        film(872585, "Oppenheimer", 2023,
             "/8Gxv8gSFCU0XGDykEGv7zR1n2ua.jpg", "/neeNHeXjMF5fXoCJRsOmkNGC7q.jpg", addedAt: daysAgo(11)),
    ]

    /// The Godfather, re-shaped with THREE owned versions — an oversized REMUX, a mid BluRay and a
    /// smaller WEB-DL — for Task 5's `titleversions` shot. `films[2]` keeps its own single source.
    static let filmWithVersions: MediaItem = {
        let godfather = films[2]
        func versionSource(_ id: String, _ resolution: String, _ tier: String, _ videoCodec: String,
                          _ audioCodec: String, _ sizeBytes: Int) -> MediaSource {
            MediaSource(torrentID: id, fileID: nil, restrictedLink: "https://real-debrid.invalid/\(id)",
                       parsed: ParsedRelease(title: godfather.title, resolution: resolution,
                                             source: tier, videoCodec: videoCodec,
                                             audioCodec: audioCodec, releaseGroup: "FGT"),
                       sizeBytes: sizeBytes)
        }
        let sources = [
            versionSource("gf-remux", "2160p", "REMUX", "HEVC", "TrueHD", 68_400_000_000),
            versionSource("gf-bluray", "1080p", "BluRay", "x264", "DTS", 14_700_000_000),
            versionSource("gf-webdl", "1080p", "WEB-DL", "H264", "AAC", 6_200_000_000),
        ]
        return MediaItem(id: godfather.id, kind: .movie, title: godfather.title, year: godfather.year,
                         sources: sources, seasons: [], tmdbID: godfather.tmdbID,
                         posterPath: godfather.posterPath, backdropPath: godfather.backdropPath,
                         overview: godfather.overview, addedAt: godfather.addedAt)
    }()

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
        overview: "A high school chemistry teacher turns to manufacturing after a cancer diagnosis.",
        addedAt: daysAgo(12))

    private static func simpleShow(_ tmdbID: Int, _ title: String, _ year: Int,
                                   _ poster: String, _ backdrop: String, addedAt: Date) -> MediaItem {
        MediaItem(id: "show:tmdb:\(tmdbID)", kind: .show, title: title, year: year, sources: [],
                 seasons: [Season(number: 1, episodes: (1...6).map { episode(1, $0, "\(tmdbID)-s1e\($0)") })],
                 tmdbID: tmdbID, posterPath: poster, backdropPath: backdrop, addedAt: addedAt)
    }

    static let shows: [MediaItem] = [
        show,
        simpleShow(19885, "Sherlock", 2010,
                  "/7WTsnHkbA0FaG6R9twfFde0I9hl.jpg", "/8rvLEmdI4gLrMO1rLqbNdnNcPFE.jpg", addedAt: daysAgo(13)),
        simpleShow(1399, "Game of Thrones", 2011,
                  "/1XS1oqL89opfnbLl8WnZY1O1uJx.jpg", "/zZqpAXxVSBtxV9qPBcscfXBcL2w.jpg", addedAt: daysAgo(14)),
    ]

    /// Canned watch state: one finished film, two mid-watch films, and the fixture show's first
    /// three S1 episodes (two finished, one mid-watch) — what the poster/episode badges render.
    /// The three unfinished rows carry distinct, ordered timestamps (Dune newest, Breaking Bad
    /// S1E3 an hour older, Interstellar two hours older) so `PreviewWatch.recentlyWatched` — which
    /// mirrors `LocalWatchStore.recent`'s "unfinished, newest first" rule — has a stable order for
    /// Home's Continue Watching rail.
    static let watch: [String: WatchState] = {
        var map: [String: WatchState] = [:]
        func set(_ key: String, source: MediaSource, position: Double, duration: Double, finished: Bool,
                updatedAt: Date = .now) {
            map[key] = WatchState(contentKey: key, sourceKey: WatchKey.source(source),
                                  positionSeconds: position, durationSeconds: duration,
                                  finished: finished, updatedAt: updatedAt)
        }
        let godfather = films[2]
        set(WatchKey.content(forMovie: godfather), source: godfather.sources[0],
           position: 8150, duration: 8160, finished: true)

        let dune = films[0]
        set(WatchKey.content(forMovie: dune), source: dune.sources[0],
           position: 3753, duration: 8160, finished: false, updatedAt: .now)

        let s1 = show.seasons.first { $0.number == 1 }!.episodes
        for ep in s1.prefix(2) {
            set(WatchKey.content(forShow: show, episode: ep), source: ep.source,
               position: 2570, duration: 2580, finished: true)
        }
        if let e3 = s1.first(where: { $0.number == 3 }) {
            set(WatchKey.content(forShow: show, episode: e3), source: e3.source,
               position: 1210, duration: 2580, finished: false, updatedAt: .now.addingTimeInterval(-3600))
        }

        let interstellar = films[4]
        set(WatchKey.content(forMovie: interstellar), source: interstellar.sources[0],
           position: 5000, duration: 10140, finished: false, updatedAt: .now.addingTimeInterval(-7200))
        return map
    }()
}

/// A fake `LibraryProviding` for the harness: no Real-Debrid, no TMDB — canned items, or a
/// scripted empty/hang/failure — so every `LibraryStore.State` can be screenshot-verified.
struct PreviewLibrary: LibraryProviding {
    enum Mode {
        case items([MediaItem]), loadingForever, failing, empty
    }
    let mode: Mode

    func loadCached() -> [MediaItem]? {
        switch mode {
        case .items(let items): return items
        case .empty: return []
        case .loadingForever, .failing: return nil
        }
    }

    func refresh() async throws -> [MediaItem] {
        switch mode {
        case .items(let items): return items
        case .empty: return []
        case .loadingForever:
            try await Task.sleep(for: .seconds(3600))
            return []
        case .failing:
            throw URLError(.notConnectedToInternet)
        }
    }

    func remove(_ item: MediaItem) async throws {}
    func removeVersion(_ item: MediaItem, source: MediaSource) async throws {}
}

/// A fake `WatchProgressProviding` over an in-memory map. Records into it, so marking watched in
/// the harness actually changes what the next read sees.
actor PreviewWatch: WatchProgressProviding, WatchRatingProviding, WatchSummaryProviding {
    private var states: [String: WatchState]
    private var ratings: [String: Int]
    private var summaries: [String: WatchSummary]
    private var since: [String: Date]

    init(_ seed: [String: WatchState] = [:], ratings: [String: Int] = [:],
        summaries: [String: WatchSummary] = [:], since: [String: Date] = [:]) {
        states = seed
        self.ratings = ratings
        self.summaries = summaries
        self.since = since
    }

    func rating(forContentKey key: String) async -> Int? { ratings[key] }
    func setRating(_ value: Int?, forContentKey key: String) async { ratings[key] = value }
    func watchSummary(forContentKey key: String) async -> WatchSummary? { summaries[key] }
    func historySince(forContentKey key: String) async -> Date? { since[key] }

    func progress(forContentKey key: String, profileID: String) async throws -> WatchState? { states[key] }

    func progress(forContentKeys keys: [String], profileID: String) async throws -> [String: WatchState] {
        keys.reduce(into: [:]) { $0[$1] = states[$1] }
    }

    func record(contentKey: String, sourceKey: String, positionSeconds: Double, durationSeconds: Double,
               finished: Bool, profileID: String) async throws {
        states[contentKey] = WatchState(contentKey: contentKey, sourceKey: sourceKey,
                                        positionSeconds: positionSeconds, durationSeconds: durationSeconds,
                                        finished: finished, updatedAt: .now)
    }

    /// Mirrors `LocalWatchStore.recent`: unfinished rows with a real position, newest first, capped
    /// at `limit` — so Home's fixture Continue Watching rail orders the same way the real store
    /// would.
    func recentlyWatched(limit: Int, profileID: String) async throws -> [WatchState] {
        Array(states.values
            .filter { !$0.finished && $0.positionSeconds > 0 }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(limit))
    }

    func deleteProgress(forContentKeys keys: [String]) async throws {
        for key in keys { states.removeValue(forKey: key) }
    }
}

/// A fake `MediaDetailsProviding` for the title-page harness: canned TMDB details for the fixture
/// film and show — real still paths for Breaking Bad S1/S2 (fetched once, like Task 3's posters),
/// no network. Season 2 lists 8 episodes against 3 owned (`Fixture.show`), so `titleshows2` shows
/// exactly "3 owned, 5 not downloaded".
struct PreviewDetails: MediaDetailsProviding {
    /// Dune: Part Two gets the real TMDB logo/cast/director/collection (fetched once against the
    /// live API — Task 3); any other fixture film degrades to the plain genres it always had.
    func movieDetails(tmdbID: Int) async throws -> TMDBMovieDetails {
        let title = Fixture.films.first { $0.tmdbID == tmdbID }?.title ?? "Film"
        guard tmdbID == 693134 else {
            return TMDBMovieDetails(id: tmdbID, title: title, releaseDate: nil, overview: nil,
                                    posterPath: nil, backdropPath: nil, runtime: 167,
                                    genres: [TMDBGenre(id: 1, name: "Science Fiction"), TMDBGenre(id: 2, name: "Adventure")],
                                    voteAverage: nil)
        }
        return TMDBMovieDetails(
            id: tmdbID, title: title, releaseDate: "2024-02-27", overview: nil,
            posterPath: nil, backdropPath: nil, runtime: 167,
            genres: [TMDBGenre(id: 1, name: "Science Fiction"), TMDBGenre(id: 2, name: "Adventure")],
            voteAverage: 8.5, originalLanguage: "en", imdbID: "tt15239678",
            cast: Self.duneCast, directors: [TMDBPersonRef(id: 137427, name: "Denis Villeneuve")],
            similar: Self.similarFilms, collection: TMDBCollectionRef(id: 726871, name: "Dune Collection"),
            images: TMDBImageSet(backdrops: [],
                                 logos: [TMDBImageRef(filePath: "/eYvF1LhPKuoBxOAmWjFTAK7EPWl.png",
                                                      languageCode: "en", voteAverage: 4.722, width: 4319)]))
    }

    /// The Dune Collection, real (fetched once) — two released films plus one unreleased (Part
    /// Three, 2026-12-15) that `FranchiseOrder` must drop, proving "Film 2 of 2" not "of 3".
    func collection(id: Int) async throws -> TMDBCollection? {
        guard id == 726871 else { return nil }
        func part(_ id: Int, _ title: String, _ date: String, _ poster: String) -> TMDBSearchResult {
            TMDBSearchResult(id: id, title: title, name: nil, releaseDate: date, firstAirDate: nil,
                             posterPath: poster, overview: nil, voteAverage: nil)
        }
        return TMDBCollection(id: 726871, name: "Dune Collection", parts: [
            part(438631, "Dune", "2021-09-15", "/d5NXSklXo0qyIYkgV94XAgMIckC.jpg"),
            part(693134, "Dune: Part Two", "2024-02-27", "/6izwz7rsy95ARzTR3poZ8H6c5pp.jpg"),
            part(1170608, "Dune: Part Three", "2026-12-15", "/d43fvHQsIMa4kpyhKXw0haEJIvI.jpg"),
        ])
    }

    private static func cast(_ id: Int, _ name: String, _ profile: String) -> TMDBCastMember {
        TMDBCastMember(id: id, name: name, character: nil, profilePath: profile)
    }

    /// Task 6's More Like This rail: real TMDB (id, title, poster) rows, none of them `Fixture`'s
    /// own Dune or Breaking Bad — reused for both the Dune movie and the Breaking Bad show fixture.
    private static func similarResult(_ id: Int, _ title: String, _ poster: String) -> TMDBSearchResult {
        TMDBSearchResult(id: id, title: title, name: nil, releaseDate: "2020-01-01", firstAirDate: nil,
                         posterPath: poster, overview: nil, voteAverage: 7.5)
    }

    static let similarFilms: [TMDBSearchResult] = [
        similarResult(27205, "Inception", "/8ZTVqvKDQ8emSGUEMjsS4yHAwrp.jpg"),
        similarResult(157336, "Interstellar", "/yQvGrMoipbRoddT0ZR8tPoR7NfX.jpg"),
        similarResult(155, "The Dark Knight", "/qJ2tW6WMUDux911r6m7haRef0WH.jpg"),
        similarResult(496243, "Parasite", "/7IiTTgloJzvGI1TAYymCfbfl3vT.jpg"),
    ]

    static let duneCast: [TMDBCastMember] = [
        cast(1190668, "Timoth\u{E9}e Chalamet", "/dFxpwRpmzpVfP1zjluH68DeQhyj.jpg"),
        cast(505710, "Zendaya", "/3WdOloHpjtjL96uVOhFRRCcYSwq.jpg"),
        cast(933238, "Rebecca Ferguson", "/ra53cM1aNmdH0aFhj8yBqPOj2fb.jpg"),
        cast(3810, "Javier Bardem", "/zfRID0jx8DKBluPGU9xtk9sZWUt.jpg"),
        cast(16851, "Josh Brolin", "/sX2etBbIkxRaCsATyw5ZpOVMPTD.jpg"),
        cast(86654, "Austin Butler", "/atdAs4pFGjUQ4m2W8kJYly7N6cC.jpg"),
        cast(1373737, "Florence Pugh", "/ejgQXt1fAvPueAvacDsGwG00aA.jpg"),
        cast(543530, "Dave Bautista", "/snk6JiXOOoRjPtHU5VMoy6qbd32.jpg"),
    ]

    /// Breaking Bad also gets its real logo/cast/creator.
    func tvDetails(tmdbID: Int) async throws -> TMDBTVDetails {
        TMDBTVDetails(id: tmdbID, name: Fixture.show.title, firstAirDate: "2008-01-20", overview: nil,
                      posterPath: nil, backdropPath: nil, numberOfSeasons: 2,
                      genres: [TMDBGenre(id: 1, name: "Crime"), TMDBGenre(id: 2, name: "Drama")],
                      voteAverage: nil, originalLanguage: "en", imdbID: "tt0903747", cast: Self.bbCast,
                      creatorRefs: [TMDBPersonRef(id: 66633, name: "Vince Gilligan")],
                      similar: Self.similarFilms,
                      images: TMDBImageSet(backdrops: [],
                                           logos: [TMDBImageRef(filePath: "/chw44B2VnLha8iiTdyZcIW0ZELC.png",
                                                                languageCode: "en", voteAverage: 6.312, width: 2184)]))
    }

    static let bbCast: [TMDBCastMember] = [
        cast(17419, "Bryan Cranston", "/7Jahy5LZX2Fo8fGJltMreAI49hC.jpg"),
        cast(84497, "Aaron Paul", "/8Ac9uuoYwZoYVAIJfRLzzLsGGJn.jpg"),
        cast(134531, "Anna Gunn", "/adppyeu1a4REN3khtgmXusrapFi.jpg"),
        cast(209674, "RJ Mitte", "/sNPA92ZrssYhlaB1UA2pWcLD9db.jpg"),
        cast(14329, "Dean Norris", "/mKRrEbsxAX3ro700HsViFArRM7l.jpg"),
        cast(1217934, "Betsy Brandt", "/xAnuzyjdMbQq9L1c4JNwXL52Wm4.jpg"),
        cast(59410, "Bob Odenkirk", "/rF0Lb6SBhGSTvjRffmlKRSeI3jE.jpg"),
        cast(783, "Jonathan Banks", "/bswk26L13PvY4iMTwUTAsepXCLv.jpg"),
    ]

    func seasonEpisodes(tvID: Int, season: Int) async throws -> [TMDBEpisodeDetails] {
        switch season {
        case 1: return Self.season1
        case 2: return Self.season2
        default: return []
        }
    }

    private static func episode(_ n: Int, _ name: String, _ still: String, _ runtime: Int) -> TMDBEpisodeDetails {
        TMDBEpisodeDetails(episodeNumber: n, name: name, overview: nil, stillPath: still, runtime: runtime, airDate: nil)
    }

    /// Breaking Bad S1 — all 6 owned by `Fixture.show`.
    static let season1: [TMDBEpisodeDetails] = [
        episode(1, "Pilot", "/88Z0fMP8a88EpQWMCs1593G0ngu.jpg", 59),
        episode(2, "Cat's in the Bag...", "/AbMoecO0ZZio0LcgeLxlzdyGs6X.jpg", 49),
        episode(3, "...And the Bag's in the River", "/2kBeBlxGqBOdWlKwzAxiwkfU5on.jpg", 49),
        episode(4, "Cancer Man", "/2UbRgW6apE4XPzhHPA726wUFyaR.jpg", 49),
        episode(5, "Gray Matter", "/82G3wZgEvZLKcte6yoZJahUWBtx.jpg", 49),
        episode(6, "Crazy Handful of Nothin'", "/rCCLuycNPL30W3BtuB8HafxEMYz.jpg", 49),
    ]

    /// Breaking Bad S2 — only the first 3 are owned by `Fixture.show`; 4–8 stay "not downloaded".
    static let season2: [TMDBEpisodeDetails] = [
        episode(1, "Seven Thirty-Seven", "/6Uo1z56uKnX60JXvYYFWACHR31u.jpg", 48),
        episode(2, "Grilled", "/th3SNe0gNgRguv8VveLd4f2JcaH.jpg", 48),
        episode(3, "Bit by a Dead Bee", "/abgJTOWYPdZGxAWhsg6lmtM8qcU.jpg", 47),
        episode(4, "Down", "/gMXeL0qcQZi5Tfd4UhnkRJeI9oa.jpg", 48),
        episode(5, "Breakage", "/bPQxF63jhfT5eNYjhzuGEO7oMQg.jpg", 48),
        episode(6, "Peekaboo", "/tfCuh20gNHGGF6A1te3NmiqML6D.jpg", 48),
        episode(7, "Negro y Azul", "/1IOnhCCeru1BZUPeppu7tMmtxvL.jpg", 48),
        episode(8, "Better Call Saul", "/KmFdF23FtbPwwz3FJF2T885r2Z.jpg", 48),
    ]
}

/// A `MediaDetailsProviding` whose details call never returns — `titlerailsloading`'s rail
/// skeletons, pinning `DetailStore.richState` at `.loading` forever.
struct PreviewHangingDetails: MediaDetailsProviding {
    func movieDetails(tmdbID: Int) async throws -> TMDBMovieDetails {
        try await Task.sleep(for: .seconds(3600))
        throw CancellationError()
    }
    func tvDetails(tmdbID: Int) async throws -> TMDBTVDetails {
        try await Task.sleep(for: .seconds(3600))
        throw CancellationError()
    }
    func seasonEpisodes(tvID: Int, season: Int) async throws -> [TMDBEpisodeDetails] { [] }
}

/// A `PersonCreditsProviding` fixture for Task 6's `-uiPreview person*` cases: Denis Villeneuve,
/// real TMDB (id, title, poster) rows for both AS DIRECTOR (6 films) and AS ACTOR (2, borrowed
/// posters — he has no notable acting credits, and the page only needs the section to render).
/// `mode` drives the three non-`.loaded` states without a second fixture type.
enum PreviewPersonMode { case loaded, empty, failed, hanging }

struct PreviewPersonCredits: PersonCreditsProviding {
    let mode: PreviewPersonMode

    func person(tmdbID: Int) async throws -> TMDBPersonDetails {
        switch mode {
        case .hanging:
            try await Task.sleep(for: .seconds(3600))
            throw CancellationError()
        case .failed: throw URLError(.badServerResponse)
        case .empty: return TMDBPersonDetails(id: tmdbID, name: "Denis Villeneuve",
                                              profilePath: "/8YGYJj0FJ5fSXHKZzo23bTNyLTB.jpg",
                                              knownForDepartment: "Directing")
        case .loaded: break
        }
        func credit(_ id: Int, _ title: String, _ poster: String,
                   job: String? = nil, character: String? = nil) -> TMDBPersonCredit {
            TMDBPersonCredit(result: TMDBSearchResult(id: id, title: title, name: nil,
                                                      releaseDate: "2020-01-01", firstAirDate: nil,
                                                      posterPath: poster, overview: nil, voteAverage: 7.5),
                             kind: .movie, character: character, job: job, popularity: 10)
        }
        let directing = [
            credit(693134, "Dune: Part Two", "/6izwz7rsy95ARzTR3poZ8H6c5pp.jpg", job: "Director"),
            credit(438631, "Dune", "/d5NXSklXo0qyIYkgV94XAgMIckC.jpg", job: "Director"),
            credit(157336, "Interstellar", "/yQvGrMoipbRoddT0ZR8tPoR7NfX.jpg", job: "Director"),
            credit(27205, "Inception", "/8ZTVqvKDQ8emSGUEMjsS4yHAwrp.jpg", job: "Director"),
            credit(155, "The Dark Knight", "/qJ2tW6WMUDux911r6m7haRef0WH.jpg", job: "Director"),
            credit(496243, "Parasite", "/7IiTTgloJzvGI1TAYymCfbfl3vT.jpg", job: "Director"),
        ]
        let acting = [
            credit(238, "The Godfather", "/3bhkrj58Vtu7enYsRolD1fZdja1.jpg", character: "Cameo"),
            credit(603, "The Matrix", "/dXNAPwY7VrqMAo51EKhhCJfaGb5.jpg", character: "Cameo"),
        ]
        return TMDBPersonDetails(id: tmdbID, name: "Denis Villeneuve",
                                 profilePath: "/8YGYJj0FJ5fSXHKZzo23bTNyLTB.jpg",
                                 knownForDepartment: "Directing", castCredits: acting, crewCredits: directing)
    }
}

/// A canned `RatingsProviding` — IMDb 8.5, RT 92%, Metacritic 79 for every imdbID asked.
struct PreviewRatings: RatingsProviding {
    func ratings(imdbID: String) async throws -> OMDbRatings {
        OMDbRatings(imdb: 8.5, rottenTomatoes: 92, metacritic: 79)
    }
}

/// A `RatingsProviding` that never resolves — `titleratingsloading`'s shimmer chips.
struct PreviewHangingRatings: RatingsProviding {
    func ratings(imdbID: String) async throws -> OMDbRatings {
        try await Task.sleep(for: .seconds(3600))
        return OMDbRatings(imdb: nil, rottenTomatoes: nil, metacritic: nil)
    }
}

/// A canned `LetterboxdRatingProviding` — 4.4 from 120,000 members for every TMDB id.
struct PreviewLetterboxd: LetterboxdRatingProviding {
    func rating(forTMDB id: Int) async throws -> LetterboxdFilmRating? {
        LetterboxdFilmRating(score: 4.4, count: 120_000)
    }
}

/// The acquisition harness: a `StreamSource` + `AddProviding` pair that `TitleAcquirer` drives
/// through fake `AcquisitionStore`/`AddStore` instances, so the not-owned title page's Play button
/// can be screenshot-verified with no Real-Debrid account. `.instant` finds a cached stream and
/// adds it straight away; `.none` finds nothing cached (the download section takes over in Task 4);
/// `.hanging` never resolves, pinning the "Finding a version…" busy state.
enum PreviewAcquireMode { case instant, none, hanging }

struct PreviewAcquireSource: StreamSource, AddProviding {
    let mode: PreviewAcquireMode

    func streams(for query: StreamQuery) async throws -> [CachedStream] {
        switch mode {
        case .instant:
            return [CachedStream(infoHash: String(repeating: "a", count: 40), fileIdx: nil,
                                 rawTitle: "Dune.Part.Two.2024.2160p.BluRay.x265",
                                 parsed: ParsedRelease(title: "Dune Part Two", resolution: "2160p",
                                                       source: "BluRay", videoCodec: "HEVC", audioCodec: "DTS-HD"),
                                 languages: ["en"], sizeBytes: 40_000_000_000, sourceName: "Preview", isCached: true)]
        case .none:
            return []
        case .hanging:
            try await Task.sleep(for: .seconds(3600))
            return []
        }
    }

    func add(infoHash: String) async throws -> TorrentInfo {
        TorrentInfo(id: "preview-torrent", filename: "Dune.Part.Two.2024.2160p.BluRay.x265.mkv",
                   hash: infoHash, bytes: 40_000_000_000, progress: 100, status: "downloaded",
                   files: [TorrentFile(id: 1, path: "Dune.Part.Two.2024.2160p.BluRay.x265.mkv",
                                       bytes: 40_000_000_000, selected: 1)],
                   links: ["https://real-debrid.invalid/preview"])
    }
}

/// Builds a `TitleAcquirer` over `PreviewAcquireSource`, for injection via `.environment(_:)` —
/// the same seam `TitlePage` reads before falling back to `session?.makeTitleAcquirer(for:)`.
@MainActor
func makePreviewAcquirer(item: MediaItem, mode: PreviewAcquireMode,
                         downloads: DownloadStore? = nil) -> TitleAcquirer {
    let source = PreviewAcquireSource(mode: mode)
    return TitleAcquirer(
        item: item,
        makeAcquisition: {
            AcquisitionStore(item: item) { kind in
                AddStore(imdbID: "tt0000000", kind: kind, originalLanguage: "en",
                        streamSource: source, add: source)
            }
        },
        makeSeasonPack: { season in
            AddStore(imdbID: "tt0000000", kind: .series(season: season, episode: 1),
                    originalLanguage: "en", streamSource: source, add: source, seasonPack: season)
        },
        downloads: downloads,
        onAdded: {})
}

/// A fixed "chosen version" — `titleversions` uses it so the ✓ lands on the BluRay row rather than
/// whichever the ranker would pick.
struct PreviewVersionPrefs: VersionPreferring {
    let sourceKey: String
    func preferred(forContentKey key: String) async -> String? { sourceKey }
    func choose(contentKey: String, sourceKey: String) async {}
    func clear(contentKey: String) async {}
}

/// A `StreamSource` + `AddProviding` pair for the Versions SHEET harness: a fixed cached/uncached
/// list (mirrors the mockup's Godfather releases — one oversized REMUX, three "Recommended"), or a
/// hang for `versionsloading`, or an `add(infoHash:)` that never returns for `versionspicking`.
enum PreviewVersionsSourceMode { case list, hangingStreams, hangingAdd }

struct PreviewVersionsSource: StreamSource, AddProviding {
    let mode: PreviewVersionsSourceMode

    static func releases() -> [CachedStream] {
        func stream(_ hash: String, _ raw: String, _ resolution: String, _ tier: String,
                   _ videoCodec: String, _ audioCodec: String, _ size: Int, cached: Bool) -> CachedStream {
            CachedStream(infoHash: String(repeating: hash, count: 40), fileIdx: nil, rawTitle: raw,
                        parsed: ParsedRelease(title: "The Godfather", resolution: resolution,
                                              source: tier, videoCodec: videoCodec, audioCodec: audioCodec),
                        languages: ["en"], sizeBytes: size, sourceName: "Preview", isCached: cached)
        }
        return [
            stream("1", "The.Godfather.1972.2160p.UHD.BluRay.REMUX.HDR.TrueHD.5.1-FGT",
                  "2160p", "REMUX", "HEVC", "TrueHD", 68_400_000_000, cached: true),
            stream("2", "The.Godfather.1972.2160p.BluRay.x265.DDP5.1-hallowed",
                  "2160p", "BluRay", "x265", "DDP", 25_000_000_000, cached: true),
            stream("3", "The.Godfather.1972.1080p.BluRay.x264.DTS-HDC",
                  "1080p", "BluRay", "x264", "DTS", 14_700_000_000, cached: true),
            stream("4", "The.Godfather.1972.1080p.WEB-DL.AAC2.0.H264-EVO",
                  "1080p", "WEB-DL", "H264", "AAC", 6_200_000_000, cached: false),
            // Hebrew inside the file (the release name says so): the lit mark on its own line.
            CachedStream(infoHash: String(repeating: "5", count: 40), fileIdx: nil,
                         rawTitle: "The.Godfather.1972.1080p.BluRay.x264.HebSubs-HDH",
                         parsed: ParsedRelease(title: "The Godfather", resolution: "1080p",
                                               source: "BluRay", videoCodec: "x264"),
                         languages: ["en"], sizeBytes: 9_800_000_000, sourceName: "Preview",
                         isCached: true, subtitleLanguages: ["he"]),
        ]
    }

    func streams(for query: StreamQuery) async throws -> [CachedStream] {
        switch mode {
        case .hangingStreams:
            try await Task.sleep(for: .seconds(3600))
            return []
        case .list, .hangingAdd:
            return Self.releases()
        }
    }

    func add(infoHash: String) async throws -> TorrentInfo {
        if mode == .hangingAdd { try await Task.sleep(for: .seconds(3600)) }
        throw URLError(.badServerResponse)
    }
}

/// A Hebrew search that answers at once with one subtitle made for the WEB-DL release, so the
/// Versions sheet draws "Hebrew · Matched" through the real `AddStore` path, not a hand-set badge.
struct PreviewSubtitleEvidence: SubtitleEvidenceProviding {
    func hebrewResults(contentKey: String, query: SubtitleQuery,
                       originalLanguage: String?) async -> [SubtitleResult]? {
        [SubtitleResult(fileID: 1, language: "he", release: "The.Godfather.1972.1080p.WEB-DL.AAC2.0.H264-EVO")]
    }
    func storedHebrewResults(contentKey: String) async -> [SubtitleResult]? { nil }
    func records(for sources: [MediaSource]) async -> [String: VersionSubtitleRecord] { [:] }
    func storedEvidence(for sources: [MediaSource], contentKey: String) async -> SubtitleEvidenceSet { .empty }
    func recordPlayback(_ tracks: [MediaTrack], for source: MediaSource) async {}
}

/// The `titleversions` film's Hebrew, through `DetailStore`'s real evidence path: the preferred
/// Blu-ray carries a Hebrew text track in its header (in the file, so the hero and its row get the
/// lit mark) and OpenSubtitles has a Hebrew subtitle made for the WEB-DL (Matched).
struct PreviewTitleSubtitleEvidence: SubtitleEvidenceProviding {
    let inFile: MediaSource
    let matchedRelease: String

    func hebrewResults(contentKey: String, query: SubtitleQuery,
                       originalLanguage: String?) async -> [SubtitleResult]? {
        [SubtitleResult(fileID: 2, language: "he", release: matchedRelease)]
    }
    func storedHebrewResults(contentKey: String) async -> [SubtitleResult]? { nil }
    func records(for sources: [MediaSource]) async -> [String: VersionSubtitleRecord] {
        [WatchKey.source(inFile): VersionSubtitleRecord(
            origin: .header, fileName: "The.Godfather.1972.1080p.BluRay.x264.DTS-FGT.mkv",
            tracks: [ContainerTrack(kind: .video, language: nil, frameRate: 23.976),
                     ContainerTrack(kind: .audio, language: "en"),
                     ContainerTrack(kind: .subtitle, language: "he", codec: "S_TEXT/UTF8")])]
    }
    func storedEvidence(for sources: [MediaSource], contentKey: String) async -> SubtitleEvidenceSet { .empty }
    func recordPlayback(_ tracks: [MediaTrack], for source: MediaSource) async {}
}

/// A canned `TrailerProviding` + `TrailerStreamResolving` pair — always resolves to a real public
/// HLS stream (the same one `VLCSmokePreview` uses), so the capsules and the inline loop can be
/// screenshot-verified with no YouTube extraction.
struct PreviewTrailerSource: TrailerProviding, TrailerStreamResolving {
    static let url = URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8")!

    func trailerKey(tmdbID: Int, kind: MediaKind) async -> String? { "preview" }
    func streamURL(youTubeKey: String) async -> URL? { Self.url }
}

@MainActor
func makePreviewTrailerModel(autoplay: Bool = true) -> TrailerModel {
    let source = PreviewTrailerSource()
    return TrailerModel(trailers: source, resolver: source, autoplayEnabled: { autoplay })
}

/// A no-op engine that relays emitted events — enough to drive `PlayerModel` end to end with no
/// VLCKit. Port of `Apps/SeretMobile/Playback/PlayerUIPreview.swift`'s `MobilePreviewEngine`, plus
/// `play()`/`pause()` emitting `.state(.playing)`/`.state(.paused)` so the harness transport (Space,
/// the play/pause button) actually moves the model.
@MainActor
final class PreviewEngine: VideoPlayerEngine {
    var audioTracks: [MediaTrack] = []
    var subtitleTracks: [MediaTrack] = []
    let events: AsyncStream<PlaybackEvent>
    private let continuation: AsyncStream<PlaybackEvent>.Continuation
    private var attachedSubtitleURLs: [URL] = []

    init() {
        var c: AsyncStream<PlaybackEvent>.Continuation!
        events = AsyncStream { c = $0 }
        continuation = c
    }

    func emit(_ event: PlaybackEvent) { continuation.yield(event) }

    func load(url: URL, headers: [String: String], audioLanguage: String?, audioTrackID: String?) {}
    func play() { emit(.state(.playing)) }
    func pause() { emit(.state(.paused)) }
    func stop() { continuation.finish() }
    func seek(to seconds: Double) {}
    func setRate(_ rate: Double) {}
    func selectAudioTrack(id: String?) {}
    func selectSubtitleTrack(id: String?) {}

    /// Surface a slave the way VLCKit does — named "Track N", with NO language, never twice for the
    /// same URL.
    func addExternalSubtitle(url: URL) {
        guard !attachedSubtitleURLs.contains(url) else { return }
        attachedSubtitleURLs.append(url)
        subtitleTracks.append(MediaTrack(id: "ext/\(attachedSubtitleURLs.count)", kind: .subtitle,
                                         name: "Track \(subtitleTracks.count + 1)",
                                         language: nil, isExternal: true, codec: "subt"))
        emit(.tracksChanged)
    }
}

/// Drives a `PlayerModel` over `PreviewEngine` with no VLCKit and no network, so every player
/// `-uiPreview` case shows real model state (phase, tracks, playhead) rather than hand-placed view
/// fields. `failing` makes the load itself fail, so the failure text shown is the shared model's own
/// ("The Real-Debrid link could not be opened.") rather than a harness-invented string.
@MainActor
@Observable
final class PlayerPreviewDriver {
    let engine = PreviewEngine()
    let model: PlayerModel

    /// `hangs`: the unrestrict never returns, so `PlayerScreen`'s own `.onAppear { model.start() }`
    /// begins loading but never gets past it — `phase` stays `.preparing` and the cold-open overlay
    /// (title + "Preparing…" + shimmer) stays on screen, which is what "not primed" (`playerloading`)
    /// needs to show. `failing` throws instead, so the failure text shown is the shared model's own.
    /// `episode` plays the fixture show instead of the fixture film — what `playerupnext` needs, so
    /// `hasNextEpisode` is real and `maybeShowUpNext()` (internal to `PlayerModel`) sets
    /// `upNextVisible` for real rather than the harness faking a setter that does not exist.
    init(item: MediaItem = Fixture.films[0], episode: Episode? = nil, failing: Bool = false, hangs: Bool = false) {
        let source = episode?.source ?? item.sources[0]
        let label = episode.map { DetailStore.episodeLabel(showTitle: item.title, season: $0.season, number: $0.number) }
            ?? item.title
        let contentKey = episode.map { WatchKey.content(forShow: item, episode: $0) } ?? WatchKey.content(forMovie: item)
        let request = PlaybackRequest(item: item, source: source, resumeAt: nil,
                                      label: label, contentKey: contentKey, episode: episode)
        let unrestrict: (String) async throws -> URL
        if hangs {
            unrestrict = { _ in try await Task.sleep(for: .seconds(3600)); return URL(string: "https://example.invalid/film.mkv")! }
        } else if failing {
            unrestrict = { _ in throw URLError(.timedOut) }
        } else {
            unrestrict = { _ in URL(string: "https://example.invalid/film.mkv")! }
        }
        model = PlayerModel(request: request, engine: engine, unrestrict: unrestrict,
                            recordProgress: { _, _, _, _, _ in }, subtitles: nil, loadTimeout: 3600)
    }

    /// `start()`, then the sequence a real play makes: tracks discovered, `.playing`, and a moving
    /// playhead (two ticks — the second is what marks the first rendered frame) — so the HUD is
    /// screenshot-verified against real model state, not hand-placed fields. `selectAudioTrackID`,
    /// when given, is applied the way an explicit viewer pick would be (`model.selectAudio(id:)`) —
    /// with no `trackPreferences` wired, nothing selects a track on its own.
    func prime(selectAudioTrackID: String? = nil) async {
        model.start()
        try? await Task.sleep(for: .milliseconds(50))
        engine.audioTracks = [
            MediaTrack(id: "audio/0", kind: .audio, name: "English 5.1 (E-AC-3)", language: "en", codec: "eac3"),
            MediaTrack(id: "audio/1", kind: .audio, name: "Commentary with Denis Villeneuve - English 2.0 (AAC) - [eng]", language: "en", codec: "mp4a"),
        ]
        engine.subtitleTracks = [
            MediaTrack(id: "spu/0", kind: .subtitle, name: "English", language: "en", codec: "subt"),
            MediaTrack(id: "spu/1", kind: .subtitle, name: "English SDH", language: "en", codec: "subt"),
            MediaTrack(id: "spu/2", kind: .subtitle, name: "עברית", language: "he", codec: "subt"),
        ]
        engine.emit(.tracksChanged)
        engine.emit(.state(.playing))
        engine.emit(.time(.init(position: 3752, duration: 8160)))
        try? await Task.sleep(for: .milliseconds(30))
        if let selectAudioTrackID { model.selectAudio(id: selectAudioTrackID) }
        engine.emit(.time(.init(position: 3753, duration: 8160)))
        try? await Task.sleep(for: .milliseconds(30))
    }

    /// For `playerupnext`: play right up to the model's own Up Next threshold, so
    /// `maybeShowUpNext()` — internal to `PlayerModel`, not something this harness can fake — sets
    /// `upNextVisible` and starts the real countdown. Needs a driver built with an `episode` (the
    /// fixture show's S1E1) so `hasNextEpisode` is true.
    func primeNearEpisodeEnd() async {
        model.start()
        try? await Task.sleep(for: .milliseconds(50))
        engine.emit(.state(.playing))
        engine.emit(.time(.init(position: 2555, duration: 2580)))   // past the ~30s-from-end threshold
        try? await Task.sleep(for: .milliseconds(80))
    }
}

/// `DiscoverProviding` fixture for Task 6's `-uiPreview browse*` cases: 30 real (tmdbID, title,
/// year, poster) rows, split across rails so `DiscoverStore`'s cross-rail dedup doesn't erase any
/// of them — `trending(.day)` gets rows 0..<12 (238 The Godfather, watched in `Fixture.watch`, and
/// 693134 Dune: Part Two, owned via `Fixture.films`, are both in it), `trending(.week)` gets
/// 12..<24, and every other rail falls back to 24..<30. `nowPlayingMovies()` returns one id already
/// in the day rail, so that poster carries the CAM badge. `hanging` never resolves (what
/// `browseloading` needs — the segment stays `.loading`, no spinner); `failing` returns `[]`
/// everywhere, so every rail is empty and the segment ends `.failed`.
struct PreviewDiscover: DiscoverProviding {
    enum Mode { case normal, hanging, failing }
    let mode: Mode

    /// `fileprivate`, not `private`: `PreviewGenres` (below, same file) reuses the same real poster
    /// paths so the genre grid's screenshot shows real artwork too.
    fileprivate static let table: [(Int, String, Int, String)] = [
        (693134, "Dune: Part Two", 2024, "/6izwz7rsy95ARzTR3poZ8H6c5pp.jpg"),
        (73, "American History X", 1998, "/x2drgoXYZ8484lqyDj7L1CEVR4T.jpg"),
        (762504, "Nope", 2022, "/AcKVlWaNVVVFQwro3nLXqPljcYA.jpg"),
        (238, "The Godfather", 1972, "/3bhkrj58Vtu7enYsRolD1fZdja1.jpg"),
        (340666, "Nocturnal Animals", 2016, "/mdLDgQBD0va09npSQX5Zgo2evXM.jpg"),
        (103663, "The Hunt", 2012, "/jkixsXzRh28q3PCqFoWcf7unghT.jpg"),
        (701387, "Bugonia", 2025, "/rSdOua3wKMEaFWDcKAYWRjXQWOt.jpg"),
        (26513, "Punishment Park", 1971, "/fPGnMnp80ycqUHdgP1T3nzCyYKe.jpg"),
        (406, "La Haine", 1995, "/hY4exng4s29RzDbtQInjx9MA3PZ.jpg"),
        (26719, "House of Games", 1987, "/4i27Ut4cIoLbcNpW7aeuUQErEPE.jpg"),
        (1592, "Primal Fear", 1996, "/qJf2TzE8nRTFbFMPJNW6c8mI0KU.jpg"),
        (4553, "The Machinist", 2004, "/diAYqR4xdF9Hnj7qun6DEQhRrT2.jpg"),
        (2649, "The Game", 1997, "/4UOa079915QjiTA2u5hT2yKVgUu.jpg"),
        (655, "Paris, Texas", 1984, "/sP27Qm4THyRZyHjHYMfIDtJP6YE.jpg"),
        (274, "The Silence of the Lambs", 1991, "/uS9m8OBk1A8eM9I042bx8XXpqAq.jpg"),
        (62, "2001: A Space Odyssey", 1968, "/ve72VxNqjGM69Uky4WTo2bK6rfq.jpg"),
        (28, "Apocalypse Now", 1979, "/gQB8Y5RCMkv2zwzFHbUJX3kAhvA.jpg"),
        (117, "The Untouchables", 1987, "/tPq0R4jTO4Ey8ZspFaWK9wGA4Ls.jpg"),
        (424, "Schindler's List", 1993, "/sF1U4EUQS8YHUYjNl3pMGNIQyr0.jpg"),
        (380, "Rain Man", 1988, "/iTNHwO896WKkaoPtpMMS74d8VNi.jpg"),
        (500, "Reservoir Dogs", 1992, "/xi8Iu6qyTfyZVDVy60raIOYJJmk.jpg"),
        (968, "Dog Day Afternoon", 1975, "/mavrhr0ig2aCRR8d48yaxtD5aMQ.jpg"),
        (510, "One Flew Over the Cuckoo's Nest", 1975, "/kjWsMh72V6d8KRLV4EOoSJLT1H7.jpg"),
        (1018, "Mulholland Drive", 2001, "/x7A59t6ySylr1L7aubOQEA480vM.jpg"),
        (769, "GoodFellas", 1990, "/9OkCLM73MIU2CrKZbqiT8Ln1wY2.jpg"),
        (98, "Gladiator", 2000, "/wN2xWp1eIwCKOD0BHTcErTBv1Uq.jpg"),
        (7345, "There Will Be Blood", 2007, "/fa0RDkAlCec0STeMNAhPaF89q6U.jpg"),
        (77016, "End of Watch", 2012, "/pDeVKQICkcdwwjHxGj0MeS14YJ6.jpg"),
        (496243, "Parasite", 2019, "/7IiTTgloJzvGI1TAYymCfbfl3vT.jpg"),
        (901563, "Close", 2022, "/dlMNnWs7Mz8Nk5AC447Ew1tD5pn.jpg"),
    ]

    private func result(_ i: Int) -> TMDBSearchResult {
        let (id, title, year, poster) = Self.table[i]
        return TMDBSearchResult(id: id, title: title, name: nil, releaseDate: "\(year)-01-01",
                                firstAirDate: nil, posterPath: poster, overview: nil, voteAverage: 7.5)
    }

    private func slice(_ range: Range<Int>) -> [TMDBSearchResult] { range.map(result) }

    private func respond(_ hits: [TMDBSearchResult]) async throws -> [TMDBSearchResult] {
        switch mode {
        case .normal: return hits
        case .hanging: try await Task.sleep(for: .seconds(3600)); return []
        case .failing: return []
        }
    }

    func nowPlayingMovies() async throws -> [TMDBSearchResult] { try await respond([result(6)]) }

    func trending(_ kind: MediaKind, window: TMDBTrendingWindow) async throws -> [TMDBSearchResult] {
        try await respond(window == .day ? slice(0..<12) : slice(12..<24))
    }
    func topRatedCurated(_ kind: MediaKind) async throws -> [TMDBSearchResult] { try await respond(slice(24..<30)) }
    func newOverall(_ kind: MediaKind, from: String, to: String) async throws -> [TMDBSearchResult] {
        try await respond(slice(24..<30))
    }
    func decade(_ kind: MediaKind, from: String, to: String) async throws -> [TMDBSearchResult] {
        try await respond(slice(24..<30))
    }
    func recommended(_ kind: MediaKind, tmdbID: Int) async throws -> [TMDBSearchResult] {
        try await respond(slice(24..<30))
    }
    func newByGenre(_ kind: MediaKind, _ genreID: Int, from: String, to: String) async throws -> [TMDBSearchResult] {
        try await respond(slice(24..<30))
    }
    func popularByGenre(_ kind: MediaKind, _ genreID: Int) async throws -> [TMDBSearchResult] {
        try await respond(slice(24..<30))
    }
    func topRatedByGenre(_ kind: MediaKind, _ genreID: Int) async throws -> [TMDBSearchResult] {
        try await respond(slice(24..<30))
    }
}

/// `GenreBrowsing` fixture for `-uiPreview genre`: 20 titles on pages 1 and 2, then nothing — so
/// `GenreGridStore.loadMore()` reaches its end after two pages rather than climbing toward the
/// real 10-page cap, and the footer skeleton row disappears once scrolled that far.
struct PreviewGenres: GenreBrowsing {
    func titles(kind: MediaKind, genreID: Int, sort: GenreSort, page: Int) async throws -> [TMDBSearchResult] {
        guard page <= 2 else { return [] }
        return (0..<20).map { i in
            let n = (page - 1) * 20 + i
            let (_, _, _, poster) = PreviewDiscover.table[n % PreviewDiscover.table.count]
            return TMDBSearchResult(id: 900_000 + n, title: "Genre Title \(n + 1)", name: nil,
                                    releaseDate: "2020-01-01", firstAirDate: nil,
                                    posterPath: poster, overview: nil, voteAverage: 7)
        }
    }
}

/// `SearchProviding` fixture for Task 7's `-uiPreview search*` cases: 8 films out of
/// `PreviewDiscover.table` (including 238 The Godfather, watched in `Fixture.watch`, and 693134
/// Dune: Part Two, owned via `Fixture.films`) plus two shows — Breaking Bad (1396, owned) and
/// Stranger Things (66732, NOT owned — `Fixture.shows` already owns Sherlock/19885, so that one
/// would show the owned disc too) — so a results grid shows every badge at once.
struct PreviewSearch: SearchProviding {
    enum Mode { case results, empty, failing, hanging }
    let mode: Mode

    private static let filmIndices = [0, 1, 2, 3, 6, 7, 8, 9]

    func searchMovie(query: String, year: Int?) async throws -> [TMDBSearchResult] {
        try await respond(Self.filmIndices.map { i in
            let (id, title, y, poster) = PreviewDiscover.table[i]
            return TMDBSearchResult(id: id, title: title, name: nil, releaseDate: "\(y)-01-01",
                                    firstAirDate: nil, posterPath: poster, overview: nil, voteAverage: 7.5)
        })
    }

    func searchTV(query: String, firstAirYear: Int?) async throws -> [TMDBSearchResult] {
        try await respond([
            TMDBSearchResult(id: 1396, title: nil, name: "Breaking Bad", releaseDate: nil,
                             firstAirDate: "2008-01-01", posterPath: "/anFx9aTOOYqgS3v7x3R84Kz67ly.jpg",
                             overview: nil, voteAverage: 9.0),
            TMDBSearchResult(id: 66732, title: nil, name: "Stranger Things", releaseDate: nil,
                             firstAirDate: "2016-01-01", posterPath: "/49WJfeN0moxb9IPfGn8AIqMGskD.jpg",
                             overview: nil, voteAverage: 8.6),
        ])
    }

    private func respond(_ hits: [TMDBSearchResult]) async throws -> [TMDBSearchResult] {
        switch mode {
        case .results: return hits
        case .empty: return []
        case .failing: throw URLError(.notConnectedToInternet)
        case .hanging: try await Task.sleep(for: .seconds(3600)); return []
        }
    }
}

/// A `DownloadStore` over two canned in-flight downloads, no network — real TMDB poster paths
/// (from `Apps/SeretTV/Playback/PlayerUIPreview.swift`'s Home preview table) so the sidebar card,
/// the popover and the library strip all show real art.
enum PreviewDownloads {
    private struct FailingService: DownloadRequesting {
        func startDownload(infoHash: String) async throws -> TorrentInfo { throw URLError(.badServerResponse) }
    }

    private struct FixedRecords: DownloadRecording {
        let items: [DownloadRequestData]
        func upsert(_ data: DownloadRequestData) async throws {}
        func all() async throws -> [DownloadRequestData] { items }
        func delete(torrentID: String) async throws {}
    }

    private struct FixedPoller: DownloadPolling {
        let statuses: [DownloadStatus]
        func poll() async throws -> [DownloadStatus] { statuses }
    }

    private struct NoOpDeleter: DownloadDeleting {
        func deleteTorrent(id: String) async throws {}
    }

    private static let bugonia = DownloadRequestData(
        torrentID: "t-bugonia", contentKey: "movie:tmdb:701387", tmdbID: 701387,
        infoHash: "bugonia-hash", kind: .movie, title: "Bugonia",
        posterPath: "/rSdOua3wKMEaFWDcKAYWRjXQWOt.jpg", requestedAt: .now)
    private static let nope = DownloadRequestData(
        torrentID: "t-nope", contentKey: "movie:tmdb:762504", tmdbID: 762504,
        infoHash: "nope-hash", kind: .movie, title: "Nope",
        posterPath: "/AcKVlWaNVVVFQwro3nLXqPljcYA.jpg", requestedAt: .now)

    @MainActor
    static func store() async -> DownloadStore {
        let statuses = [
            DownloadStatus(torrentID: bugonia.torrentID, contentKey: bugonia.contentKey, tmdbID: bugonia.tmdbID,
                          phase: .downloading, fraction: 0.64, seeders: 12, secondsRemaining: 360,
                          title: bugonia.title, posterPath: bugonia.posterPath),
            DownloadStatus(torrentID: nope.torrentID, contentKey: nope.contentKey, tmdbID: nope.tmdbID,
                          phase: .downloading, fraction: 0.22, seeders: 0, secondsRemaining: nil,
                          title: nope.title, posterPath: nope.posterPath),
        ]
        let store = DownloadStore(service: FailingService(), records: FixedRecords(items: [bugonia, nope]),
                                  poller: FixedPoller(statuses: statuses), deleter: NoOpDeleter(),
                                  pollInterval: .seconds(3600))
        await store.loadActive()
        await store.refresh()
        return store
    }

    /// One movie's tracked download at a chosen phase — the title page's download section harness
    /// (`titledownloading` / `titledownloadfailed`).
    @MainActor
    static func store(forMovieTmdbID tmdbID: Int, title: String, posterPath: String?,
                      phase: DownloadStatus.Phase, fraction: Double) async -> DownloadStore {
        let contentKey = DownloadKey.movie(tmdbID: tmdbID)
        let record = DownloadRequestData(torrentID: "t-preview-\(tmdbID)", contentKey: contentKey,
                                         tmdbID: tmdbID, infoHash: "preview-hash", kind: .movie,
                                         title: title, posterPath: posterPath, requestedAt: .now)
        let status = DownloadStatus(torrentID: record.torrentID, contentKey: contentKey, tmdbID: tmdbID,
                                    phase: phase, fraction: fraction, title: title, posterPath: posterPath)
        let store = DownloadStore(service: FailingService(), records: FixedRecords(items: [record]),
                                  poller: FixedPoller(statuses: [status]), deleter: NoOpDeleter(),
                                  pollInterval: .seconds(3600))
        await store.loadActive()
        await store.refresh()
        return store
    }

    /// One episode's tracked download — Task 7's `titleshows2` (S2E5 reading "Downloading 42 %").
    @MainActor
    static func store(forEpisodeOf show: MediaItem, season: Int, number: Int, fraction: Double) async -> DownloadStore {
        let contentKey = DownloadKey.episode(showTmdbID: show.tmdbID ?? 0, season: season, number: number)
        let record = DownloadRequestData(torrentID: "t-preview-episode", contentKey: contentKey,
                                         tmdbID: show.tmdbID ?? 0, infoHash: "preview-hash", kind: .show,
                                         title: "\(show.title) S\(season)E\(number)", posterPath: show.posterPath,
                                         requestedAt: .now)
        let status = DownloadStatus(torrentID: record.torrentID, contentKey: contentKey, tmdbID: show.tmdbID ?? 0,
                                    phase: .downloading, fraction: fraction, title: record.title,
                                    posterPath: show.posterPath)
        let store = DownloadStore(service: FailingService(), records: FixedRecords(items: [record]),
                                  poller: FixedPoller(statuses: [status]), deleter: NoOpDeleter(),
                                  pollInterval: .seconds(3600))
        await store.loadActive()
        await store.refresh()
        return store
    }

    /// A whole-season pack's tracked download — Task 7's `titleseasondownloading`.
    @MainActor
    static func store(forSeasonOf show: MediaItem, season: Int, fraction: Double,
                      secondsRemaining: TimeInterval?) async -> DownloadStore {
        let contentKey = DownloadKey.season(showTmdbID: show.tmdbID ?? 0, season: season)
        let record = DownloadRequestData(torrentID: "t-preview-season", contentKey: contentKey,
                                         tmdbID: show.tmdbID ?? 0, infoHash: "preview-hash", kind: .show,
                                         title: "\(show.title) Season \(season)", posterPath: show.posterPath,
                                         requestedAt: .now)
        let status = DownloadStatus(torrentID: record.torrentID, contentKey: contentKey, tmdbID: show.tmdbID ?? 0,
                                    phase: .downloading, fraction: fraction, secondsRemaining: secondsRemaining,
                                    title: record.title, posterPath: show.posterPath)
        let store = DownloadStore(service: FailingService(), records: FixedRecords(items: [record]),
                                  poller: FixedPoller(statuses: [status]), deleter: NoOpDeleter(),
                                  pollInterval: .seconds(3600))
        await store.loadActive()
        await store.refresh()
        return store
    }
}
#endif
