#if DEBUG
import DebridCore
import DebridUI
import SwiftUI

/// `-uiPreview browse`: the real Movies page (`BrowseScreen`) on a fixture `DiscoverStore`, with real
/// TMDB art for the header and backdrop, laid out inside the shell's leading inset.
///
/// The fixture's rails arrive the way the real ones do — progressively, through the store's own
/// load: For You's first two rails land within a second, the third (`More like Parasite`) 4 s in,
/// appended below. A film in cinemas carries the CAM chip.
///
/// `browseinsert` also lands a watch history 9 s in and asks the store to rebuild For You, as the
/// page does when the profile resolves: the quiet rebuild (all rails in, then one swap) adds
/// "Because you watched Oldboy" ABOVE the rails already on screen — the case where the page must
/// keep the focused rail at the top.
struct BrowseScreenPreview: View {
    var insertAbove = false

    @State private var session = AppSession(realDebrid: RealDebridSession(store: InMemoryTokenStore()))
    @State private var seeds = BrowsePreviewFixture.Seeds()
    @State private var store: DiscoverStore?
    @State private var art = TitleArtStore(details: TMDBDetailsService(
        client: TMDBClient(apiKey: Secrets.tmdbAPIKey)))

    var body: some View {
        NavigationStack {
            Group {
                if let store {
                    BrowseScreen(kind: .movie, previewBrowse: store, previewArt: art)
                } else {
                    Color.black
                }
            }
            // The shell's content inset, so x positions match the real app.
            .sideMenuContentInset()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CanvasBackground())
        }
        .environment(session)
        .task {
            let browse = DiscoverStore(kind: .movie, discover: BrowsePreviewFixture.Discover(), seeds: seeds)
            store = browse
            guard insertAbove else { return }
            try? await Task.sleep(for: .seconds(9))
            seeds.watchedOldboy = true
            await browse.refreshForYouIfBetterSeeds()
        }
    }
}

enum BrowsePreviewFixture {
    static func result(_ id: Int, _ title: String, _ year: Int?, _ poster: String?,
                       _ overview: String? = nil) -> TMDBSearchResult {
        TMDBSearchResult(id: id, title: title, name: nil, releaseDate: year.map { "\($0)-06-01" },
                         firstAirDate: nil, posterPath: poster, overview: overview, voteAverage: nil)
    }

    /// Films with a synopsis (the plexrails fixture's), first rail material.
    static let recent: [TMDBSearchResult] = (PlexRailsFixture.continueWatching + PlexRailsFixture.movies)
        .map(\.subject)
        .filter { $0.kind == .movie && $0.tmdbID != nil }
        .map { result($0.tmdbID!, $0.title, $0.year, $0.posterPath, $0.overview) }

    /// Real titles and posters, no synopsis.
    static let classics: [TMDBSearchResult] = [
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
        (670, "Oldboy", 2003, "/pWDtjs568ZfOTMbURQBYuT4Qxka.jpg"),
        (206487, "Predestination", 2014, "/38Xr1JnV1ZcLQ55zmdSp6n475cZ.jpg"),
        (598, "City of God", 2002, "/k7eYdWvhYQyRQoU2TB2A2Xu2TfD.jpg"),
        (1417, "Pan's Labyrinth", 2006, "/z7xXihu5wHuSMWymq5VAulPVuvg.jpg"),
        (950396, "The Gorge", 2025, "/7iMBZzVZtG0oBug4TfqDb9ZxAOa.jpg"),
        (451915, "Beautiful Boy", 2018, "/u2Gfv0mz3xePsgyCPHovrnFL1sB.jpg"),
        (11104, "Chungking Express", 1994, "/43I9DcNoCzpyzK8JCkJYpHqHqGG.jpg"),
        (1422, "The Departed", 2006, "/nT97ifVT2J1yMQmeq20Qblg61T.jpg"),
        (103, "Taxi Driver", 1976, "/ekstpH614fwDX8DUln1a2Opz0N8.jpg"),
        (648878, "Eddington", 2025, "/4GIqZUgPZ146BhibsPHMHef2nXX.jpg"),
        (272, "Batman Begins", 2005, "/sPX89Td70IDDjVr85jdSBb4rWGr.jpg"),
    ].map { result($0.0, $0.1, $0.2, $0.3) }

    static var pool: [TMDBSearchResult] { recent + classics }

    /// Ten titles from the pool, starting at `offset` (wrapping).
    static func slice(_ offset: Int, _ count: Int = 10) -> [TMDBSearchResult] {
        let all = pool
        return (0..<count).map { all[(offset + $0) % all.count] }
    }

    @MainActor
    final class Seeds: RecommendationSeedProviding {
        /// Flipped by `browseinsert`: a watch history has landed.
        var watchedOldboy = false

        func seeds(kind: MediaKind, limit: Int) async -> [RecommendationSeed] {
            var list = [RecommendationSeed(tmdbID: 244786, title: "Whiplash", watched: false),
                        RecommendationSeed(tmdbID: 238, title: "The Godfather", watched: false),
                        RecommendationSeed(tmdbID: 496243, title: "Parasite", watched: false)]
            if watchedOldboy {
                list.insert(RecommendationSeed(tmdbID: 670, title: "Oldboy", watched: true), at: 0)
            }
            return Array(list.prefix(limit))
        }
    }

    struct Discover: DiscoverProviding {
        private func after(_ ms: Int, _ titles: [TMDBSearchResult]) async -> [TMDBSearchResult] {
            try? await Task.sleep(for: .milliseconds(ms))
            return titles
        }

        func nowPlayingMovies() async throws -> [TMDBSearchResult] {
            recent.filter { $0.id == 969681 }       // Spider-Man: Brand New Day → CAM
        }
        func trending(_ kind: MediaKind, window: TMDBTrendingWindow) async throws -> [TMDBSearchResult] {
            await after(300, window == .day ? slice(30) : Array(recent.reversed()))
        }
        func topRatedCurated(_ kind: MediaKind) async throws -> [TMDBSearchResult] {
            await after(300, Array(classics.prefix(12)))
        }
        func newOverall(_ kind: MediaKind, from: String, to: String) async throws -> [TMDBSearchResult] {
            await after(300, recent)
        }
        func decade(_ kind: MediaKind, from: String, to: String) async throws -> [TMDBSearchResult] {
            await after(300, slice(from.count * 7 + Int(from.prefix(4))! % 40))
        }
        /// For You: Whiplash and The Godfather answer at once, Parasite 4 s later (it lands
        /// below them). Oldboy — the watch history `browseinsert` adds — answers at once too.
        func recommended(_ kind: MediaKind, tmdbID: Int) async throws -> [TMDBSearchResult] {
            switch tmdbID {
            case 244786: await after(400, recent)
            case 238:    await after(800, Array(classics[0..<10]))
            case 496243: await after(4_000, Array(classics[10..<20]))
            case 670:    await after(300, Array(classics[20..<30]))
            default:     []
            }
        }
        func newByGenre(_ kind: MediaKind, _ genreID: Int, from: String, to: String) async throws -> [TMDBSearchResult] {
            await after(300, slice(genreID % 37))
        }
        func popularByGenre(_ kind: MediaKind, _ genreID: Int) async throws -> [TMDBSearchResult] {
            await after(300, slice(genreID % 41))
        }
        func topRatedByGenre(_ kind: MediaKind, _ genreID: Int) async throws -> [TMDBSearchResult] {
            await after(300, slice(genreID % 43))
        }
    }
}
#endif
