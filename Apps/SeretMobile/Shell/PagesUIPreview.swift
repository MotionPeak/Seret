#if DEBUG
import DebridCore
import DebridUI
import SwiftUI

/// DEBUG-only harness for the redesigned pages, rendered through the REAL shell (tab bar on
/// iPhone, floating sidebar on iPad) on fixture stores, so they can be screenshot on any simulator
/// — the iPad has no signed-in session, and no simulator has a watch history to fill Continue
/// Watching without playing something.
///
///     xcrun simctl launch <udid> com.solomons.seret.mobile -uiPreview <target>
///
/// - `home` — hero (American History X, part-way), Continue Watching (incl. an up-next episode),
///   Recently Added Movies / Shows. `homedownloading` adds a Downloading rail;
///   `homedownloadsonly` has downloads and nothing else (no hero).
/// - `movies` / `shows` — the browse page's rows, arriving progressively (For You first, then
///   Trending, New, Top Rated, then a row per genre); `-browseDelay N` (ms) slows each row.
/// - `genregrid` — the Drama grid a genre row's "See All" opens, seeded from its row.
/// - `homescript` — Home, then on a timer (seconds from launch; screenshot just before the next
///   step): 10 push See All · 15 pop · 20 push again · 23 switch to Movies · 26 back to Home (the
///   art must be back) · 31 scroll down · 36 Movies · 39 Home (the art must be at the top) — the
///   iPad shell's art through every way Home leaves and returns.
/// - `watchlist`, `watchlistremove`, `watchlistremoveboth`, `watchlistremoved`, `spin`,
///   `watchlistgrid`, `watchlistsetup`, `watchlistempty` — see `WatchlistPreviewFixture`.
///
/// Art (logos, textless backdrops, ratings) is real TMDB through a real `TitleArtStore`; nothing
/// touches Real-Debrid. Add `-glassFallback` for the iOS 18 glass look.
struct PagesUIPreview: View {
    let target: String
    @State private var session = AppSession(realDebrid: RealDebridSession(store: InMemoryTokenStore()))
    @State private var router = AppRouter()
    @State private var stores: UIPreviewStores?
    @State private var started = Date()

    var body: some View {
        Group {
            if stores != nil {
                if target == "genregrid" {
                    NavigationStack {
                        GenreGridScreen(route: GenreRoute(kind: .movie,
                                                          genre: DiscoverStore.Genre(name: "Drama", tmdbID: 18),
                                                          seed: PagesFixture.pool.prefix(20).map {
                                                              SearchHit(result: $0, kind: .movie)
                                                          }))
                    }
                } else if target == "watchlistgrid", let model = stores?.watchlist {
                    NavigationStack {
                        WatchlistGridScreen(route: WatchlistGridRoute(rowID: "recent", title: "Recently Added"),
                                            model: model, details: stores?.watchlistDetails)
                    }
                } else {
                    MainShell()
                }
            } else {
                Theme.Palette.canvas.ignoresSafeArea()
            }
        }
        .environment(\.uiPreviewStores, stores)
        .environment(session)
        .environment(router)
        .environment(TileWatchMarks.placeholder)
        .environment(WatchlistMarks.placeholder)
        .preferredColorScheme(.dark)
        .tint(Theme.Palette.focus)
        .task {
            await build()
            if target == "homescript" { await runHomeScript() }
        }
    }

    private func runHomeScript() async {
        guard let script = stores?.homeScript else { return }
        func at(_ seconds: Double, _ step: () -> Void) async {
            let wait = seconds - started.timeIntervalSinceNow * -1
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            step()
        }
        await at(10) { script.pushes += 1 }
        await at(15) { script.pops += 1 }
        await at(20) { script.pushes += 1 }
        await at(23) { router.selectedSection = .movies }
        await at(26) { router.selectedSection = .home }
        await at(31) { script.scrollTo = HomeRailID.shows }
        await at(36) { router.selectedSection = .movies }
        await at(39) { script.scrollTo = nil; router.selectedSection = .home }
    }

    private func build() async {
        router.selectedSection = switch target {
        case "movies": .movies
        case "shows": .shows
        case _ where target.hasPrefix("watchlist") || target == "spin": .watchlist
        default: .home
        }
        let home = HomeStore(watch: PagesFixture.Watch())
        home.activeProfileID = "preview"
        // `homedownloadsonly`: nothing watched, nothing in the library — only a download under way,
        // so Home has no hero and its first rail must start below the header.
        let downloadsOnly = target == "homedownloadsonly"
        await home.rebuild(movies: downloadsOnly ? [] : PagesFixture.movies,
                           shows: downloadsOnly ? [] : PagesFixture.shows)
        let delay = UserDefaults.standard.integer(forKey: "browseDelay")
        stores = UIPreviewStores(
            home: home,
            art: TitleArtStore(details: TMDBDetailsService(client: TMDBClient(apiKey: Secrets.tmdbAPIKey))),
            downloads: target == "homedownloading" ? [PagesFixture.download]
                : downloadsOnly ? [PagesFixture.download, PagesFixture.noArtDownload] : [],
            moviesBrowse: DiscoverStore(kind: .movie, discover: PagesFixture.Discover(delay: delay),
                                        seeds: PagesFixture.Seeds()),
            showsBrowse: DiscoverStore(kind: .show, discover: PagesFixture.Discover(delay: delay),
                                       seeds: nil),
            genreBrowsing: PagesFixture.Genres(),
            homeScript: target == "homescript" ? HomePreviewScript() : nil)
        if target.hasPrefix("watchlist") || target == "spin" { buildWatchlist() }
    }

    private func buildWatchlist() {
        let tmdb = TMDBDetailsService(client: TMDBClient(apiKey: Secrets.tmdbAPIKey))
        let model = WatchlistPreviewFixture.model(empty: target == "watchlistempty")
        let details = WatchlistDetailsStore(fileURL: nil, details: tmdb)
        stores?.watchlist = model
        stores?.watchlistDetails = details
        stores?.watchlistConnected = target != "watchlistsetup"
        stores?.watchlistArt = tmdb
        switch target {
        case "watchlistremove": stores?.watchlistScript = WatchlistPreviewScript(confirmRemovalOf: "f4")      // Mother — Noga's only
        case "watchlistremoveboth": stores?.watchlistScript = WatchlistPreviewScript(confirmRemovalOf: "f2")  // American Beauty — both
        case "watchlistremoved": stores?.watchlistScript = WatchlistPreviewScript(removeSlug: "f0")           // Stalker
        case "spin": stores?.watchlistScript = WatchlistPreviewScript(spins: true)
        default: break
        }
        if target == "watchlistgrid" {
            Task { await details.ensure(WatchlistPreviewFixture.entries.compactMap(\.tmdbID)) }
        }
    }
}

enum PagesFixture {
    // MARK: Home

    /// Two part-way entries (a film and an episode) and one finished episode, whose show comes
    /// back as "Next".
    struct Watch: WatchProgressProviding {
        func recentlyWatched(limit: Int, profileID: String) async throws -> [WatchState] {
            [WatchState(contentKey: "movie:tmdb:73", sourceKey: "t#1", positionSeconds: 2_880,
                        durationSeconds: 7_140, finished: false, updatedAt: Date()),
             WatchState(contentKey: "movie:tmdb:1018", sourceKey: "t#22", positionSeconds: 3_000,
                        durationSeconds: 8_820, finished: false, updatedAt: Date().addingTimeInterval(-30)),
             WatchState(contentKey: "show:tmdb:95557:s3e1", sourceKey: "t#2", positionSeconds: 240,
                        durationSeconds: 2_700, finished: false, updatedAt: Date().addingTimeInterval(-60)),
             WatchState(contentKey: "movie:tmdb:496243", sourceKey: "t#27", positionSeconds: 5_100,
                        durationSeconds: 7_920, finished: false, updatedAt: Date().addingTimeInterval(-90)),
             WatchState(contentKey: "movie:tmdb:655", sourceKey: "t#12", positionSeconds: 1_200,
                        durationSeconds: 8_700, finished: false, updatedAt: Date().addingTimeInterval(-100))]
        }
        func recentlyFinished(limit: Int, profileID: String) async throws -> [WatchState] {
            [WatchState(contentKey: "show:tmdb:95396:s1e1", sourceKey: "t#3", positionSeconds: 3_300,
                        durationSeconds: 3_300, finished: true, updatedAt: Date().addingTimeInterval(-120))]
        }
        func progress(forContentKey key: String, profileID: String) async throws -> WatchState? { nil }
        func record(contentKey: String, sourceKey: String, positionSeconds: Double,
                    durationSeconds: Double, finished: Bool, profileID: String) async throws {}
        func deleteProgress(forContentKeys keys: [String]) async throws {}
    }

    private static func source(_ id: String) -> MediaSource {
        MediaSource(torrentID: id, fileID: 1, restrictedLink: "rd://\(id)",
                    parsed: ParsedRelease(title: "T", resolution: "2160p"))
    }

    private static let films: [(Int, String, Int, String)] = [
        (73, "American History X", 1998, "/x2drgoXYZ8484lqyDj7L1CEVR4T.jpg"),
        (762504, "Nope", 2022, "/AcKVlWaNVVVFQwro3nLXqPljcYA.jpg"),
        (238, "The Godfather", 1972, "/3bhkrj58Vtu7enYsRolD1fZdja1.jpg"),
        (340666, "Nocturnal Animals", 2016, "/mdLDgQBD0va09npSQX5Zgo2evXM.jpg"),
        (103663, "The Hunt", 2012, "/jkixsXzRh28q3PCqFoWcf7unghT.jpg"),
        (701387, "Bugonia", 2025, "/rSdOua3wKMEaFWDcKAYWRjXQWOt.jpg"),
        (406, "La Haine", 1995, "/hY4exng4s29RzDbtQInjx9MA3PZ.jpg"),
        (1592, "Primal Fear", 1996, "/qJf2TzE8nRTFbFMPJNW6c8mI0KU.jpg"),
        (4553, "The Machinist", 2004, "/diAYqR4xdF9Hnj7qun6DEQhRrT2.jpg"),
        (2649, "The Game", 1997, "/4UOa079915QjiTA2u5hT2yKVgUu.jpg"),
        (655, "Paris, Texas", 1984, "/sP27Qm4THyRZyHjHYMfIDtJP6YE.jpg"),
        (274, "The Silence of the Lambs", 1991, "/uS9m8OBk1A8eM9I042bx8XXpqAq.jpg"),
        (62, "2001: A Space Odyssey", 1968, "/ve72VxNqjGM69Uky4WTo2bK6rfq.jpg"),
        (28, "Apocalypse Now", 1979, "/gQB8Y5RCMkv2zwzFHbUJX3kAhvA.jpg"),
        (1018, "Mulholland Drive", 2001, "/x7A59t6ySylr1L7aubOQEA480vM.jpg"),
        (769, "GoodFellas", 1990, "/9OkCLM73MIU2CrKZbqiT8Ln1wY2.jpg"),
        (7345, "There Will Be Blood", 2007, "/fa0RDkAlCec0STeMNAhPaF89q6U.jpg"),
        (496243, "Parasite", 2019, "/7IiTTgloJzvGI1TAYymCfbfl3vT.jpg"),
        (670, "Oldboy", 2003, "/pWDtjs568ZfOTMbURQBYuT4Qxka.jpg"),
        (598, "City of God", 2002, "/k7eYdWvhYQyRQoU2TB2A2Xu2TfD.jpg"),
        (1417, "Pan's Labyrinth", 2006, "/z7xXihu5wHuSMWymq5VAulPVuvg.jpg"),
        (11104, "Chungking Express", 1994, "/43I9DcNoCzpyzK8JCkJYpHqHqGG.jpg"),
        (1422, "The Departed", 2006, "/nT97ifVT2J1yMQmeq20Qblg61T.jpg"),
        (103, "Taxi Driver", 1976, "/ekstpH614fwDX8DUln1a2Opz0N8.jpg"),
        (155, "The Dark Knight", 2008, "/qJ2tW6WMUDux911r6m7haRef0WH.jpg"),
        (577922, "Tenet", 2020, "/aCIFMriQh8rvhxpN1IWGgvH0Tlg.jpg"),
        (503919, "The Lighthouse", 2019, "/yAKNmpcUweGH6WMCEWenwU9PsbE.jpg"),
        (1124, "The Prestige", 2006, "/Ag2B2KHKQPukjH7WutmgnnSNurZ.jpg"),
    ]

    private static let overviews: [Int: String] = [
        73: "A former neo-Nazi skinhead tries to prevent his younger brother from going down the same wrong path that he did.",
        95557: "Mark Grayson is a normal teenager — except for the fact that his father is the most powerful superhero on the planet.",
        95396: "Mark leads a team of office workers whose memories have been surgically divided between their work and personal lives.",
    ]

    static var movies: [MediaItem] {
        films.enumerated().map { i, row in
            let (tmdb, title, year, poster) = row
            return MediaItem(id: "movie:tmdb:\(tmdb)", kind: .movie, title: title, year: year,
                             sources: [source("t\(i)")], seasons: [], tmdbID: tmdb, posterPath: poster,
                             overview: overviews[tmdb],
                             addedAt: Date().addingTimeInterval(-Double(i) * 3_600))
        }
    }

    static var shows: [MediaItem] {
        let rows: [(Int, String, Int, String)] = [
            (95557, "INVINCIBLE", 2021, "/4tblBrslcKSifMVZ3TmtT2ukMor.jpg"),
            (95396, "Severance", 2022, "/pPHpeI2X1qEd1CS1SeyrdhZ4qnT.jpg"),
            (247718, "MobLand", 2025, "/5Xc7WpWsgflfgEMoBlf9TmWhfbH.jpg"),
            (153312, "Tulsa King", 2022, "/rOYLWCdAifpUtPlTf1WHxyaxeMt.jpg"),
            (203857, "The Diplomat", 2023, "/cUy0ZYme43lop08nOtbQLWL0dX.jpg"),
            (123542, "LINK CLICK", 2021, "/hCt2bLRGTCjHGqtV5FP3Img6w1h.jpg"),
            (30984, "Bleach", 2004, "/2EewmxXe72ogD0EaWM8gqa0ccIw.jpg"),
            (37854, "One Piece", 1999, "/dB4EDhre2dsC2kxYDavyKWqLQwi.jpg"),
        ]
        return rows.enumerated().map { i, row in
            let (tmdb, title, year, poster) = row
            let episodes = [Episode(season: 1, number: 1, source: source("t-\(tmdb)-1")),
                            Episode(season: 1, number: 2, source: source("t-\(tmdb)-2"))]
            let seasons = tmdb == 95557
                ? [Season(number: 3, episodes: [Episode(season: 3, number: 1, source: source("t-inv"))])]
                : [Season(number: 1, episodes: episodes)]
            return MediaItem(id: "show:tmdb:\(tmdb)", kind: .show, title: title, year: year,
                             sources: [], seasons: seasons, tmdbID: tmdb, posterPath: poster,
                             overview: overviews[tmdb],
                             addedAt: Date().addingTimeInterval(-Double(i) * 5_400))
        }
    }

    static let download = DownloadTile(
        tmdbID: 693134, title: "Dune: Part Two", posterPath: "/1pdfLvkbY9ohJlCjQH2CZjjYVvJ.jpg",
        status: DownloadStatus(torrentID: "dl-693134", contentKey: "movie:tmdb:693134", tmdbID: 693134,
                               phase: .downloading, fraction: 0.42, speedBytesPerSecond: 12_000_000,
                               secondsRemaining: 540, title: "Dune: Part Two",
                               posterPath: "/1pdfLvkbY9ohJlCjQH2CZjjYVvJ.jpg"))

    /// No poster: the title on a surface, never a blank card.
    static let noArtDownload = DownloadTile(
        tmdbID: 0, title: "גבעת חלפון אינה עונה", posterPath: nil,
        status: DownloadStatus(torrentID: "dl-0", contentKey: "movie:tmdb:0", tmdbID: 0,
                               phase: .downloading, fraction: 0.08, speedBytesPerSecond: 3_000_000,
                               secondsRemaining: nil, title: "גבעת חלפון אינה עונה", posterPath: nil))

    // MARK: Browse

    static var pool: [TMDBSearchResult] {
        films.map { TMDBSearchResult(id: $0.0, title: $0.1, name: nil, releaseDate: "\($0.2)-06-01",
                                     firstAirDate: nil, posterPath: $0.3, overview: nil, voteAverage: nil) }
    }

    /// `count` pool titles from `offset`, wrapping.
    static func slice(_ offset: Int, _ count: Int = 12) -> [TMDBSearchResult] {
        let all = pool
        return (0..<count).map { all[(offset + $0) % all.count] }
    }

    @MainActor
    final class Seeds: RecommendationSeedProviding {
        func seeds(kind: MediaKind, limit: Int) async -> [RecommendationSeed] {
            Array([RecommendationSeed(tmdbID: 244786, title: "Whiplash", watched: true),
                   RecommendationSeed(tmdbID: 496243, title: "Parasite", watched: false)].prefix(limit))
        }
    }

    /// Every call answers after `delay` ms plus a stagger, so rows land one by one.
    struct Discover: DiscoverProviding {
        var delay = 0
        private func after(_ ms: Int, _ titles: [TMDBSearchResult]) async -> [TMDBSearchResult] {
            try? await Task.sleep(for: .milliseconds(ms + delay))
            return titles
        }
        func nowPlayingMovies() async throws -> [TMDBSearchResult] { [pool[5]] }   // Bugonia → CAM
        func trending(_ kind: MediaKind, window: TMDBTrendingWindow) async throws -> [TMDBSearchResult] {
            await after(300, slice(window == .day ? 9 : 3))
        }
        func topRatedCurated(_ kind: MediaKind) async throws -> [TMDBSearchResult] { await after(400, slice(11)) }
        func newOverall(_ kind: MediaKind, from: String, to: String) async throws -> [TMDBSearchResult] {
            await after(350, slice(5))
        }
        func decade(_ kind: MediaKind, from: String, to: String) async throws -> [TMDBSearchResult] {
            await after(300, slice(Int(from.prefix(4))! % 28))
        }
        func recommended(_ kind: MediaKind, tmdbID: Int) async throws -> [TMDBSearchResult] {
            await after(tmdbID == 244786 ? 200 : 900, slice(tmdbID % 28))
        }
        func newByGenre(_ kind: MediaKind, _ genreID: Int, from: String, to: String) async throws -> [TMDBSearchResult] {
            await after(300, slice(genreID % 23))
        }
        func popularByGenre(_ kind: MediaKind, _ genreID: Int) async throws -> [TMDBSearchResult] {
            await after(500 + genreID % 7 * 150, slice(genreID % 27))
        }
        func topRatedByGenre(_ kind: MediaKind, _ genreID: Int) async throws -> [TMDBSearchResult] {
            await after(300, slice(genreID % 19))
        }
    }

    /// A genre grid: twenty pool titles per page, offset by genre, sort and page.
    struct Genres: GenreBrowsing {
        func titles(kind: MediaKind, genreID: Int, sort: GenreSort, page: Int) async throws -> [TMDBSearchResult] {
            try? await Task.sleep(for: .milliseconds(600))
            let sortOffset = GenreSort.allCases.firstIndex(of: sort) ?? 0
            return slice(genreID % 23 + sortOffset * 5 + (page - 1) * 20, 20)
        }
    }
}
#endif
