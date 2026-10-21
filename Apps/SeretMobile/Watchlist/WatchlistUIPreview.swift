#if DEBUG
import DebridCore
import DebridUI
import SwiftUI

/// DEBUG-only fixtures for the Watchlist harnesses (`PagesUIPreview`):
///
/// - `watchlist` — the page with a partner (Noga): every row — In Your Library, Recently Added,
///   Highest Rated, You Both Want to See, Noga's Picks, genres, Short Ones, Classics, Not Matched —
///   with the Both / Noga chips. Details come from the real TMDB API (no file), so the rating,
///   genre and runtime rows settle in as on a first visit.
/// - `watchlistremove` — 5 s in, the removal confirmation for a film only Noga holds (the wording
///   that says it stays on hers). `watchlistremoveboth` — the same for a film on both lists.
/// - `watchlistremoved` — 5 s in, a removal goes through the fixture model (it writes nowhere):
///   the film leaves every row and the count drops by one.
/// - `spin` — 5 s in, Surprise Me.
/// - `watchlistgrid` — In Your Library's See All grid. `watchlistsetup` — Letterboxd not set up.
///   `watchlistempty` — set up, nothing on the list.
enum WatchlistPreviewFixture {
    /// Name, year, TMDB id, poster, and whose list: "o" the owner's, "p" Noga's, "b" both.
    static let films: [(String, Int, Int?, String?, Character)] = [
        ("Stalker (1979)", 1979, 1398, "/1qhOyf5C4s9ZdvY8d5JDx9DFMeT.jpg", "o"),
        ("Eraserhead (1977)", 1977, 985, "/mxveW3mGVc0DzLdOmtkZsgd7c3B.jpg", "o"),
        ("American Beauty (1999)", 1999, 14, "/wby9315QzVKdW9BonAefg8jGTTb.jpg", "b"),
        ("Honey Don't! (2025)", 2025, 1149504, "/fJm3kmd9NLZWypMas7g34oNFgbk.jpg", "o"),
        ("Mother (2009)", 2009, 30018, "/8oBnSkZE6GDVugAbLPO6uJd4GcS.jpg", "p"),
        ("Ocean's Eleven (2001)", 2001, 161, "/hQQCdZrsHtZyR6NbKH2YyCqd2fR.jpg", "o"),
        ("Grave of the Fireflies (1988)", 1988, 12477, "/k9tv1rXZbOhH7eiCk378x61kNQ1.jpg", "b"),
        ("Parasite (2019)", 2019, 496243, "/7IiTTgloJzvGI1TAYymCfbfl3vT.jpg", "o"),
        ("Incendies (2010)", 2010, 46738, "/yH6DAQVgbyj72S66gN4WWVoTjuf.jpg", "p"),
        ("The Brutalist (2024)", 2024, 549509, "/vP7Yd6couiAaw9jgMd5cjMRj3hQ.jpg", "o"),
        ("It's a Wonderful Life (1946)", 1946, 1585, "/bSqt9rhDZx1Q7UZ86dBPKdNomp2.jpg", "p"),
        ("Anora (2024)", 2024, 1064213, "/cgXk2tNYhJZLXdBDO5DidAVzQ82.jpg", "b"),
        ("Nosferatu (2024)", 2024, 426063, "/5qGIxdEO841C0tdY8vOdLoRVrr0.jpg", "o"),
        ("Heat (1995)", 1995, 949, "/umSVjVdbVwtx5ryCA2QXL44Durm.jpg", "o"),
        ("Speed (1994)", 1994, 1637, "/82PkCE4R95KhHICUDF7G4Ly2z3l.jpg", "o"),
        ("Whiplash (2014)", 2014, 244786, "/7fn624j5lj3xTme2SgiLCeuedmO.jpg", "b"),
        ("Arrival (2016)", 2016, 329865, "/pEzNVQfdzYDzVK0XqxERIw2x2se.jpg", "o"),
        ("Dune (2021)", 2021, 438631, "/v1tRXZ4JtD2Iv6fjkPvT4GiwslV.jpg", "p"),
        // Resolved and found nothing — the Not Matched row.
        ("A Film TMDB Has Never Heard Of (2019)", 2019, nil, nil, "o"),
    ]

    static var entries: [WatchlistEntry] {
        films.enumerated().map { index, film in
            WatchlistEntry(slug: "f\(index)", name: film.0, year: film.1, position: index,
                           tmdbID: film.2, posterPath: film.3, resolvedAt: Date())
        }
    }

    static var owners: [WatchlistEntry] { pick { $0 == "o" || $0 == "b" } }
    static var partners: [WatchlistEntry] { pick { $0 == "p" || $0 == "b" } }

    private static func pick(_ holder: (Character) -> Bool) -> [WatchlistEntry] {
        zip(films, entries).filter { holder($0.0.4) }.map(\.1)
    }

    /// A model over the fixture. Its remove and relay are the defaults — a removal is marked in
    /// memory and goes nowhere (no mirror on disk, no Letterboxd, no server).
    @MainActor
    static func model(empty: Bool = false) -> WatchlistModel {
        let list = empty ? [] : entries
        let status = WatchlistCombinedStatus(
            membership: WatchlistMembership(owner: empty ? [] : owners, partner: empty ? [] : partners),
            partnerName: "Noga", partnerError: nil)
        let model = WatchlistModel(cached: list, settings: LetterboxdSettings(username: "preview"),
                                   status: { status }) { _ in list }
        // Four of them are already in the library: Stalker, Eraserhead, Parasite, Heat.
        model.ownedTMDBIDs = [1398, 985, 496243, 949]
        return model
    }
}
#endif
