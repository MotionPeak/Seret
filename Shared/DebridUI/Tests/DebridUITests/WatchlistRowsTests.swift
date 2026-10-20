import Testing
import Foundation
@testable import DebridUI
@testable import DebridCore

/// The Apple TV Watchlist page's rows: pure — entries + TMDB details + ownership + whose list
/// each film is on, in; the ordered rows, out.
@Suite struct WatchlistRowsTests {

    private func entry(_ slug: String, _ position: Int, id: Int?, year: Int? = 2000) -> WatchlistEntry {
        WatchlistEntry(slug: slug, name: "\(slug) (\(year ?? 2000))", year: year, position: position,
                       tmdbID: id, posterPath: id.map { "/\($0).jpg" }, resolvedAt: Date())
    }

    private func details(_ id: Int, genres: [String] = [], runtime: Int? = nil,
                         vote: Double? = nil, votes: Int? = nil) -> WatchlistFilmDetails {
        WatchlistFilmDetails(tmdbID: id, genres: genres, runtimeMinutes: runtime, voteAverage: vote,
                             voteCount: votes, overview: nil, backdropPath: nil, logoPath: nil,
                             fetchedAt: Date(timeIntervalSince1970: 0))
    }

    private func rows(_ entries: [WatchlistEntry], details: [WatchlistFilmDetails] = [],
                      owned: Set<Int> = [], owner: [WatchlistEntry]? = nil,
                      partner: [WatchlistEntry]? = nil, partnerName: String? = nil) -> [WatchlistRow] {
        let membership = partner.map { WatchlistMembership(owner: owner ?? entries, partner: $0) }
        return WatchlistRows.build(entries: entries,
                                   details: Dictionary(uniqueKeysWithValues: details.map { ($0.tmdbID, $0) }),
                                   isOwned: { $0.tmdbID.map(owned.contains) ?? false },
                                   membership: membership, partnerName: partnerName)
    }

    @Test func rowsComeInTheApprovedOrder() {
        let a = entry("a", 0, id: 1, year: 1975)
        let b = entry("b", 1, id: 2)
        let c = entry("c", 2, id: 3)
        let d = entry("d", 3, id: 4)
        let built = rows([a, b, c, d],
                         details: [details(1, genres: ["Drama"], runtime: 90, vote: 8.1, votes: 900),
                                   details(2, genres: ["Drama", "Thriller"], runtime: 130, vote: 7.0, votes: 900),
                                   details(3, genres: ["Thriller"], runtime: 95, vote: 6.0, votes: 900),
                                   details(4, genres: ["Comedy"], runtime: 120, vote: 7.5, votes: 900)],
                         owned: [2],
                         owner: [a, b, c], partner: [b, d], partnerName: "Noga")
        #expect(built.map(\.id) == ["library", "recent", "rated", "both", "partner",
                                    "genre-Drama", "genre-Thriller", "genre-Comedy",
                                    "short", "classics"])
        #expect(built.map(\.title) == ["In Your Library", "Recently Added", "Highest Rated",
                                       "You Both Want to See", "Noga's Picks",
                                       "Drama", "Thriller", "Comedy", "Short Ones", "Classics"])
        #expect(built.first { $0.id == "library" }?.subtitle == "ready to play")
        #expect(built.first { $0.id == "both" }?.subtitle == "on both lists")
        #expect(built.first { $0.id == "short" }?.subtitle == "under 100 minutes")
        #expect(built.first { $0.id == "classics" }?.subtitle == "before 1980")
    }

    @Test func emptyRowsAreSkipped() {
        let built = rows([entry("a", 0, id: 1)])
        #expect(built.map(\.id) == ["recent"])
    }

    @Test func recentlyAddedIsNewestFirstByPosition() {
        let built = rows([entry("old", 5, id: 1), entry("new", 0, id: 2), entry("mid", 2, id: 3)])
        #expect(built.first { $0.id == "recent" }?.entries.map(\.slug) == ["new", "mid", "old"])
    }

    @Test func libraryRowHoldsOnlyOwnedFilms() {
        let built = rows([entry("a", 0, id: 1), entry("b", 1, id: 2), entry("c", 2, id: 3)], owned: [3, 1])
        #expect(built.first { $0.id == "library" }?.entries.map(\.slug) == ["a", "c"])
    }

    @Test func highestRatedSortsByVoteAndDropsThinVotes() {
        let built = rows([entry("a", 0, id: 1), entry("b", 1, id: 2), entry("c", 2, id: 3),
                          entry("d", 3, id: 4), entry("e", 4, id: 5)],
                         details: [details(1, vote: 7.0, votes: 5000),
                                   details(2, vote: 9.5, votes: 12),     // too few voters
                                   details(3, vote: 8.2, votes: 200),    // exactly enough
                                   details(4, vote: 7.9),                // count unknown: kept
                                   details(5, vote: 0, votes: 900)])     // unrated
        #expect(built.first { $0.id == "rated" }?.entries.map(\.slug) == ["c", "d", "a"])
    }

    @Test func highestRatedTiesKeepListOrder() {
        let built = rows([entry("a", 0, id: 1), entry("b", 1, id: 2)],
                         details: [details(2, vote: 8, votes: 900), details(1, vote: 8, votes: 900)])
        #expect(built.first { $0.id == "rated" }?.entries.map(\.slug) == ["a", "b"])
    }

    @Test func bothAndPartnerRowsFollowMembership() {
        let mine = entry("mine", 0, id: 1)
        let shared = entry("shared", 1, id: 2)
        let hers = entry("hers", 2, id: 3)
        let built = rows([mine, shared, hers], owner: [mine, shared], partner: [shared, hers],
                         partnerName: "Noga")
        #expect(built.first { $0.id == "both" }?.entries.map(\.slug) == ["shared"])
        #expect(built.first { $0.id == "partner" }?.entries.map(\.slug) == ["hers"])
    }

    @Test func noPartnerMeansNoBothOrPartnerRows() {
        let built = rows([entry("a", 0, id: 1)], owner: [entry("a", 0, id: 1)], partner: [],
                         partnerName: nil)
        #expect(!built.contains { $0.id == "both" || $0.id == "partner" })
    }

    @Test func genreRowsUseShortNamesOrderedByCountAndCapped() {
        var entries: [WatchlistEntry] = []
        var info: [WatchlistFilmDetails] = []
        // 12 genres, genre i on (13 - i) films — so the order is by count, and two fall off.
        let names = ["Drama", "Thriller", "Comedy", "Crime", "Science Fiction", "Mystery", "Horror",
                     "Romance", "Action", "Adventure", "Fantasy", "War"]
        for n in 0..<13 {
            let id = n + 1
            entries.append(entry("f\(n)", n, id: id))
            info.append(details(id, genres: names.enumerated().filter { $0.offset < 13 - n }.map(\.element)))
        }
        let genreRows = rows(entries, details: info).filter { $0.id.hasPrefix("genre-") }
        #expect(genreRows.map(\.title) == ["Drama", "Thriller", "Comedy", "Crime", "Sci-Fi", "Mystery",
                                           "Horror", "Romance", "Action", "Adventure"])
        #expect(genreRows.count == WatchlistRows.maxGenreRows)
    }

    @Test func genreTiesBreakByName() {
        let built = rows([entry("a", 0, id: 1)], details: [details(1, genres: ["Thriller", "Drama"])])
        #expect(built.filter { $0.id.hasPrefix("genre-") }.map(\.title) == ["Drama", "Thriller"])
    }

    @Test func tvMovieIsNotAGenreRow() {
        let built = rows([entry("a", 0, id: 1)], details: [details(1, genres: ["TV Movie"])])
        #expect(!built.contains { $0.id.hasPrefix("genre-") })
    }

    @Test func shortOnesAreUnderOneHundredMinutes() {
        let built = rows([entry("a", 0, id: 1), entry("b", 1, id: 2), entry("c", 2, id: 3),
                          entry("d", 3, id: 4)],
                         details: [details(1, runtime: 99), details(2, runtime: 100),
                                   details(3, runtime: 0), details(4, runtime: 45)])
        #expect(built.first { $0.id == "short" }?.entries.map(\.slug) == ["a", "d"])
    }

    @Test func classicsAreBefore1980() {
        let built = rows([entry("a", 0, id: 1, year: 1979), entry("b", 1, id: 2, year: 1980),
                          entry("c", 2, id: 3, year: nil), entry("d", 3, id: 4, year: 1931)])
        #expect(built.first { $0.id == "classics" }?.entries.map(\.slug) == ["a", "d"])
    }

    @Test func unmatchedFilmsOnlyLiveInTheirOwnLastRow() {
        let built = rows([entry("x", 0, id: nil, year: 1950), entry("a", 1, id: 1)], owned: [])
        #expect(built.map(\.id) == ["recent", "unmatched"])
        #expect(built.last?.title == "Not Matched")
        #expect(built.last?.entries.map(\.slug) == ["x"])
        #expect(built.first?.entries.map(\.slug) == ["a"])
    }

    @Test func rowIDsAreStableAsDetailsArrive() {
        let entries = [entry("a", 0, id: 1), entry("b", 1, id: 2)]
        let before = rows(entries).map(\.id)
        let after = rows(entries, details: [details(1, genres: ["Drama"], runtime: 80, vote: 8, votes: 900)])
            .map(\.id)
        // Every row that was there is still there, in the same relative order.
        #expect(after.filter(before.contains) == before)
    }

    // MARK: - Badges and header tags

    @Test func badgesNameWhoseListAFilmIsOn() {
        let mine = entry("mine", 0, id: 1)
        let shared = entry("shared", 1, id: 2)
        let hers = entry("hers", 2, id: 3)
        let membership = WatchlistMembership(owner: [mine, shared], partner: [shared, hers])
        #expect(WatchlistRows.badge(for: mine, membership: membership, partnerName: "Noga") == nil)
        #expect(WatchlistRows.badge(for: shared, membership: membership, partnerName: "Noga") == "Both")
        #expect(WatchlistRows.badge(for: hers, membership: membership, partnerName: "Noga") == "Noga")
        #expect(WatchlistRows.badge(for: shared, membership: membership, partnerName: nil) == nil)
    }

    @Test func headerTagsSayLibraryAndWhoseList() {
        let shared = entry("shared", 1, id: 2)
        let hers = entry("hers", 2, id: 3)
        let membership = WatchlistMembership(owner: [shared], partner: [shared, hers])
        #expect(WatchlistRows.tags(for: shared, owned: true, membership: membership, partnerName: "Noga")
                == ["In Library", "Both of you"])
        #expect(WatchlistRows.tags(for: hers, owned: false, membership: membership, partnerName: "Noga")
                == ["Noga's pick"])
        #expect(WatchlistRows.tags(for: hers, owned: false, membership: nil, partnerName: nil) == [])
    }

    // MARK: - Details

    @Test func detailsComeFromTheMovieDetailsCall() {
        let movie = TMDBMovieDetails(id: 7, title: "Seven", releaseDate: "1995-09-22",
                                     overview: "Two detectives.", posterPath: "/p.jpg",
                                     backdropPath: "/b.jpg", runtime: 127,
                                     genres: [TMDBGenre(id: 80, name: "Crime")],
                                     voteAverage: 8.4, voteCount: 21000)
        let when = Date(timeIntervalSince1970: 100)
        let d = WatchlistFilmDetails(movie: movie, fetchedAt: when)
        #expect(d == WatchlistFilmDetails(tmdbID: 7, genres: ["Crime"], runtimeMinutes: 127,
                                          voteAverage: 8.4, voteCount: 21000,
                                          overview: "Two detectives.", backdropPath: "/b.jpg",
                                          logoPath: nil, fetchedAt: when))
        #expect(d.titleArt == TitleArt(logoPath: nil, backdropPath: "/b.jpg", voteAverage: 8.4,
                                       genres: ["Crime"], runtimeMinutes: 127, seasonCount: nil))
    }
}
