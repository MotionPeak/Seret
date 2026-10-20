#if DEBUG
import DebridCore
import DebridUI
import SwiftUI

/// `-uiPreview library`: the real `MyLibraryScreen` on a fixture library — real TMDB posters and
/// backdrops, through the store's own load — with two downloads in flight above the grid, inside
/// the shell's leading inset. Focus starts on the Movies pill (the screen's own focus rules), and
/// the backdrop follows focus into the grid.
///
/// `downloadChange` changes the downloads on a schedule (seconds from launch), for the strip's
/// hold rules (`LibraryScreen`):
///   - `.ends` (`-uiPreview librarydownloadends`): both downloads finish 14 s in. Walk to a lower
///     row first: the focused cell must not move. On grid row 1 the held cards show, settled
///     ("Ready", dimmed, no progress) — never frozen at their last percent.
///   - `.starts` (`-uiPreview librarydownloadstarts`): both downloads start 14 s in, from none.
///   - `.focusedEnds` (`-uiPreview librarydownloadfocusedends`): Dune finishes 12 s in while its card
///     is focused and the other carries on; the other finishes 22 s in. Move to the pills between
///     the two: the strip must go at 22 s (a removed card's focus must not hold it forever).
struct MyLibraryScreenPreview: View {
    enum DownloadChange { case ends, starts, focusedEnds }
    var downloadChange: DownloadChange?

    @State private var session = AppSession(realDebrid: RealDebridSession(store: InMemoryTokenStore()))
    @State private var downloads: [DownloadTile] = []
    @State private var library: LibraryStore?
    @State private var art = TitleArtStore(details: TMDBDetailsService(
        client: TMDBClient(apiKey: Secrets.tmdbAPIKey)))

    var body: some View {
        NavigationStack {
            Group {
                if let library {
                    MyLibraryScreen(previewLibrary: library, previewArt: art, previewDownloads: downloads,
                                    previewSettledPhase: .ready)
                } else {
                    Color.clear
                }
            }
            .sideMenuContentInset()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .environment(session)
        .environment(session.makeTileWatchMarks())
        .task {
            let both = [DownloadPreviewFixture.dune, DownloadPreviewFixture.noArt]
            let steps: [(seconds: Int, tiles: [DownloadTile])] = switch downloadChange {
            case nil: []
            case .ends: [(14, [])]
            case .starts: [(14, both)]
            case .focusedEnds: [(12, [DownloadPreviewFixture.noArt]), (22, [])]
            }
            downloads = downloadChange == .starts ? [] : both
            let start = ContinuousClock.now
            let store = LibraryStore(library: GridPreviewFixture.Listing())
            await store.load()
            library = store
            for step in steps {
                try? await Task.sleep(until: start + .seconds(step.seconds))
                downloads = step.tiles
            }
        }
    }
}

/// `-uiPreview search`: the real `SearchScreen` with "dune" already typed, answered by a fixture
/// search (real TMDB titles and posters) and real art for the backdrop.
struct SearchScreenPreview: View {
    @State private var session = AppSession(realDebrid: RealDebridSession(store: InMemoryTokenStore()))
    @State private var search = SearchStore(search: GridPreviewFixture.Search())
    @State private var art = TitleArtStore(details: TMDBDetailsService(
        client: TMDBClient(apiKey: Secrets.tmdbAPIKey)))

    var body: some View {
        NavigationStack {
            SearchScreen(kind: .movie, previewSearch: search, previewArt: art, query: "dune")
        }
        .environment(session)
        .environment(session.makeTileWatchMarks())
    }
}

enum GridPreviewFixture {
    /// (kind, TMDB id, title, year, poster, backdrop) — real TMDB data.
    static let titles: [(MediaKind, Int, String, Int, String, String)] = [
        (.movie, 693134, "Dune: Part Two", 2024, "/6izwz7rsy95ARzTR3poZ8H6c5pp.jpg", "/eZ239CUp1d6OryZEBPnO2n87gMG.jpg"),
        (.movie, 335984, "Blade Runner 2049", 2017, "/gajva2L0rPYkEWjzgFlBXCAVBE5.jpg", "/gNdLJU9TxrpGx4dkZidjys3fyy0.jpg"),
        (.movie, 273481, "Sicario", 2015, "/lz8vNyXeidqqOdJW9ZjnDAMb5Vr.jpg", "/fKPgObonYgPgCdu88yjV7Hpn7Dp.jpg"),
        (.movie, 146233, "Prisoners", 2013, "/uhviyknTT5cEQXbn6vWIqfM4vGm.jpg", "/3RFmTz5h2UuFWEV4oH00XICBR9y.jpg"),
        (.movie, 329865, "Arrival", 2016, "/pEzNVQfdzYDzVK0XqxERIw2x2se.jpg", "/8MUZz7oPXQftFTslZpRP3CVMOoq.jpg"),
        (.movie, 438631, "Dune", 2021, "/v1tRXZ4JtD2Iv6fjkPvT4GiwslV.jpg", "/qVgZu5BTx6pu4owCvVOm4zjTfOi.jpg"),
        (.movie, 949, "Heat", 1995, "/umSVjVdbVwtx5ryCA2QXL44Durm.jpg", "/uI22JkEMediWyiRqhllNqeeGtW0.jpg"),
        (.movie, 496243, "Parasite", 2019, "/7IiTTgloJzvGI1TAYymCfbfl3vT.jpg", "/TU9NIjwzjoKPwQHoHshkFcQUCG.jpg"),
        (.movie, 244786, "Whiplash", 2014, "/7fn624j5lj3xTme2SgiLCeuedmO.jpg", "/fRGxZuo7jJUWQsVg9PREb98Aclp.jpg"),
        (.movie, 670, "Oldboy", 2003, "/pWDtjs568ZfOTMbURQBYuT4Qxka.jpg", "/rwf5SUTiEsmfkXAgy15R0UtJUtv.jpg"),
        (.movie, 238, "The Godfather", 1972, "/3bhkrj58Vtu7enYsRolD1fZdja1.jpg", "/ejdD20cdHNFAYAN2DlqPToXKyzx.jpg"),
        (.movie, 181886, "Enemy", 2014, "/vf40tyDRKZsBmaLsYeopzfFLzLx.jpg", "/deYWtXTc56YdXyIuuMuA8dvBY16.jpg"),
        (.movie, 46738, "Incendies", 2010, "/yH6DAQVgbyj72S66gN4WWVoTjuf.jpg", "/f3ATwil5vmUeTsogBaMEKbBYBth.jpg"),
        (.show, 95396, "Severance", 2022, "/pPHpeI2X1qEd1CS1SeyrdhZ4qnT.jpg", "/ixgFmf1X59PUZam2qbAfskx2gQr.jpg"),
        (.show, 136315, "The Bear", 2022, "/eKfVzzEazSIjJMrw9ADa2x8ksLz.jpg", "/aJtG4txtmiRHwAAqENQHZvBs6kY.jpg"),
        (.show, 76331, "Succession", 2018, "/z0XiwdrCQ9yVIr4O0pxzaAYRxdW.jpg", "/d87JXX3DLkRJMfm5StCmmnmhHuX.jpg"),
        (.show, 1396, "Breaking Bad", 2008, "/anFx9aTOOYqgS3v7x3R84Kz67ly.jpg", "/tsRy63Mu5cu8etL1X7ZLyf7UP1M.jpg"),
        (.show, 87108, "Chernobyl", 2019, "/hlLXt2tOPT6RRnjiUmoxyG1LTFi.jpg", "/900tHlUYUkp7Ol04XFSoAaEIXcT.jpg"),
    ]

    static var items: [MediaItem] {
        titles.enumerated().map { index, t in
            let source = MediaSource(torrentID: "t-\(t.1)", fileID: 1, restrictedLink: "rd://\(t.1)",
                                     parsed: ParsedRelease(title: t.2, year: t.3, resolution: "2160p"))
            let seasons = t.0 == .show
                ? [Season(number: 1, episodes: [Episode(season: 1, number: 1, source: source)])]
                : []
            return MediaItem(id: "\(t.0.rawValue):tmdb:\(t.1)", kind: t.0, title: t.2, year: t.3,
                             sources: t.0 == .movie ? [source] : [], seasons: seasons, tmdbID: t.1,
                             posterPath: t.4, backdropPath: t.5,
                             addedAt: Date().addingTimeInterval(-Double(index) * 3_600))
        }
    }

    struct Listing: LibraryProviding {
        func loadCached() -> [MediaItem]? { GridPreviewFixture.items }
        func refresh() async throws -> [MediaItem] { GridPreviewFixture.items }
        func remove(_ item: MediaItem) async throws {}
        func removeVersion(_ item: MediaItem, source: MediaSource) async throws {}
    }

    /// Movie search: the fixture's films, with "Dune" ones first — and a title TMDB has no
    /// poster for, which the grid must still caption and print.
    struct Search: SearchProviding {
        func searchMovie(query: String, year: Int?) async throws -> [TMDBSearchResult] {
            let films = GridPreviewFixture.titles.filter { $0.0 == .movie }
            let matching = films.filter { $0.2.localizedCaseInsensitiveContains(query) }
            let rest = films.filter { !$0.2.localizedCaseInsensitiveContains(query) }
            return (matching + rest).map {
                TMDBSearchResult(id: $0.1, title: $0.2, name: nil, releaseDate: "\($0.3)-06-01",
                                 firstAirDate: nil, posterPath: $0.4, overview: nil, voteAverage: 7)
            } + [TMDBSearchResult(id: 9_999_001, title: "Dune Drifter", name: nil,
                                  releaseDate: "2020-01-01", firstAirDate: nil, posterPath: nil,
                                  overview: nil, voteAverage: 4)]
        }
        func searchTV(query: String, firstAirYear: Int?) async throws -> [TMDBSearchResult] {
            GridPreviewFixture.titles.filter { $0.0 == .show }.map {
                TMDBSearchResult(id: $0.1, title: nil, name: $0.2, releaseDate: nil,
                                 firstAirDate: "\($0.3)-01-01", posterPath: $0.4, overview: nil,
                                 voteAverage: 8)
            }
        }
    }
}
#endif
