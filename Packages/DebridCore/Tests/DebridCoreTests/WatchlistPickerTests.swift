import Testing
import Foundation
@testable import DebridCore

private func film(_ slug: String, year: Int? = 2000, rating: Int? = nil) -> LetterboxdEntry {
    LetterboxdEntry(slug: slug, name: "\(slug) (\(year ?? 0))", year: year, rating: rating)
}

/// A resolved, unremoved watchlist row. The TMDB id defaults to something derived from the
/// position so two rows never share one by accident.
private func row(_ slug: String, _ position: Int, tmdb: Int?? = .some(nil), year: Int? = 2000,
                 removed: Bool = false) -> WatchlistEntry {
    let id: Int? = tmdb ?? nil
    return WatchlistEntry(slug: slug, name: "\(slug) (\(year ?? 0))", year: year, position: position,
                          tmdbID: id ?? 1000 + position, posterPath: nil, resolvedAt: Date(),
                          removedAt: removed ? Date(timeIntervalSince1970: 100) : nil)
}

private func slugs(_ picks: [WatchlistPick]) -> [String] { picks.map(\.entry.slug) }

@Suite struct WatchlistPickerTests {

    @Test func closeMatchesComeFirstAndFollowRecency() {
        // B is listed first on the watchlist, so only the recency weight can put A ahead of it.
        let inputs = WatchlistPickInputs(
            recentFilms: [film("newest", rating: 9), film("oldest", rating: 9)],
            similar: ["newest": ["a"], "oldest": ["b"]],
            candidates: [row("b", 0), row("a", 1)])
        let picks = WatchlistPicker.pick(inputs)
        #expect(slugs(picks) == ["a", "b"])
        #expect(picks.map(\.tier) == [.close, .close])
        #expect(picks[0].score == 1.0)                       // 1.0 recency × 1.0 liking × 1.0 position
        let oldest = 1.0 - 0.7 * 1.0 / Double(WatchlistPicker.referenceCount - 1)
        #expect(abs(picks[1].score - oldest) < 1e-9)
    }

    @Test func aDislikedFilmIsNotAReference() {
        let recent = [film("hated", rating: 3), film("loved", rating: 10)]
        #expect(WatchlistPicker.references(recent).map(\.slug) == ["loved"])

        let inputs = WatchlistPickInputs(
            recentFilms: recent,
            similar: ["hated": ["from-hated"], "loved": ["from-loved"]],
            candidates: [row("from-hated", 0), row("from-loved", 1)])
        #expect(slugs(WatchlistPicker.pick(inputs)) == ["from-loved"])
    }

    @Test func referencesKeepPageOrderAndStopAtTheCount() {
        var recent = [film("skipped", rating: 2)]
        recent += (0..<40).map { film("f\($0)", rating: 8) }
        let refs = WatchlistPicker.references(recent)
        #expect(refs.count == WatchlistPicker.referenceCount)
        #expect(refs.first?.slug == "f0")
        #expect(refs.last?.slug == "f29")
    }

    @Test func directorThenLooserThenGenreFillTheRow() {
        // Listed in the opposite order to the expected result, so only the tiers can sort them.
        let inputs = WatchlistPickInputs(
            recentFilms: [film("ref", year: 2000, rating: 9)],
            similar: ["ref": ["hop"]],
            secondHop: ["hop": ["looser"]],
            directorFilms: ["ref": ["director"]],
            referenceGenres: ["ref": ["Drama", "Crime"]],
            candidates: [row("genre", 0, tmdb: 1, year: 2005), row("looser", 1, tmdb: 2),
                         row("director", 2, tmdb: 3)],
            candidateGenres: [1: ["drama"]])
        let picks = WatchlistPicker.pick(inputs)
        #expect(slugs(picks) == ["director", "looser", "genre"])
        #expect(picks.map(\.tier) == [.director, .loose, .genre])
        #expect(abs(picks[0].score - 0.5) < 1e-9)           // 0.5 × recency 1 × liking 1
        #expect(abs(picks[1].score - 0.25) < 1e-9)          // 0.25 × 1 × 1 × position-of-the-hop 1
        #expect(abs(picks[2].score - 0.1) < 1e-9)           // 0.1 × 1 × 1 × 1 shared genre
    }

    /// The central ranking rule: a tier is never beaten by a higher score from a lower tier. A
    /// score-only sort would put D (about 1.43) ahead of C (0.24).
    @Test func aCloserTierBeatsAHigherScoreFromALowerOne() {
        let filler = (1...39).map { "filler\($0)" }
        let inputs = WatchlistPickInputs(
            recentFilms: [film("unrated"), film("r1", rating: 10), film("r2", rating: 10),
                          film("r3", rating: 10)],
            similar: ["unrated": filler + ["c"]],           // "c" is 40th: position weight 0.4
            directorFilms: ["r1": ["d"], "r2": ["d"], "r3": ["d"]],
            candidates: [row("d", 0), row("c", 1)])         // D is first on the watchlist, too
        let picks = WatchlistPicker.pick(inputs)
        #expect(slugs(picks) == ["c", "d"])
        #expect(picks.map(\.tier) == [.close, .director])
        #expect(abs(picks[0].score - 0.24) < 1e-9)          // 1.0 recency x 0.6 unrated x 0.4
        #expect(picks[1].score > 1.0)                       // the lower tier does outscore it
    }

    @Test func aWeakerSignalAddsToScoreButNotTier() {
        let inputs = WatchlistPickInputs(
            recentFilms: [film("ref", rating: 10)],
            similar: ["ref": ["both"]],
            directorFilms: ["ref": ["both"]],
            candidates: [row("both", 0)])
        let pick = WatchlistPicker.pick(inputs)[0]
        #expect(pick.tier == .close)
        #expect(abs(pick.score - 1.5) < 1e-9)
    }

    @Test func similarPositionDecidesTheWeight() {
        let long = (1...40).map { "s\($0)" }
        let inputs = WatchlistPickInputs(
            recentFilms: [film("ref", rating: 10)],
            similar: ["ref": long],
            candidates: [row("s1", 0), row("s12", 1), row("s13", 2), row("s36", 3), row("s37", 4)])
        let scores = Dictionary(uniqueKeysWithValues:
            WatchlistPicker.pick(inputs).map { ($0.entry.slug, $0.score) })
        #expect(scores["s1"] == 1.0)
        #expect(scores["s12"] == 1.0)
        #expect(scores["s13"] == 0.7)
        #expect(scores["s36"] == 0.7)
        #expect(scores["s37"] == 0.4)
    }

    @Test func likingScalesTheSignal() {
        func score(_ rating: Int?) -> Double? {
            let inputs = WatchlistPickInputs(
                recentFilms: [film("ref", rating: rating)],
                similar: ["ref": ["c"]],
                candidates: [row("c", 0)])
            return WatchlistPicker.pick(inputs).first?.score
        }
        #expect(score(nil) == 0.6)
        #expect(score(10) == 1.0)
        #expect(score(9) == 1.0)
        #expect(score(8) == 0.8)
        #expect(score(7) == 0.8)
        #expect(score(6) == 0.5)
        #expect(score(5) == 0.5)
        #expect(score(4) == nil)
    }

    @Test func genreNeedsASharedGenreAndNearbyYears() {
        func picked(candidateYear: Int?, genres: [String]) -> Bool {
            let inputs = WatchlistPickInputs(
                recentFilms: [film("ref", year: 2000, rating: 9)],
                referenceGenres: ["ref": ["Thriller"]],
                candidates: [row("c", 0, tmdb: 7, year: candidateYear)],
                candidateGenres: [7: genres])
            return !WatchlistPicker.pick(inputs).isEmpty
        }
        #expect(picked(candidateYear: 2012, genres: ["THRILLER"]))        // 12 years, case-insensitive
        #expect(!picked(candidateYear: 2013, genres: ["Thriller"]))       // 13 years
        #expect(!picked(candidateYear: nil, genres: ["Thriller"]))        // unknown year
        #expect(!picked(candidateYear: 2000, genres: ["Comedy"]))         // nothing shared
    }

    @Test func bothListsGetABump() {
        // Equal signals; A is the newer watchlist row, so only the bump can put B ahead.
        let a = row("a", 0, tmdb: 1), b = row("b", 1, tmdb: 2)
        let inputs = WatchlistPickInputs(
            recentFilms: [film("ref", rating: 10)],
            similar: ["ref": ["a", "b"]],
            candidates: [a, b],
            membership: WatchlistMembership(owner: [a, b], partner: [b]))
        let picks = WatchlistPicker.pick(inputs)
        #expect(slugs(picks) == ["b", "a"])
        #expect(abs(picks[0].score - 1.15) < 1e-9)
        #expect(picks[1].score == 1.0)
    }

    @Test func unmatchedAndRemovedEntriesAreNeverPicked() {
        let unmatched = WatchlistEntry(slug: "unmatched", name: "unmatched (2000)", year: 2000,
                                       position: 0, tmdbID: nil, resolvedAt: Date())
        let inputs = WatchlistPickInputs(
            recentFilms: [film("ref", rating: 9)],
            similar: ["ref": ["unmatched", "removed", "fine"]],
            candidates: [unmatched, row("removed", 1, removed: true), row("fine", 2)])
        #expect(slugs(WatchlistPicker.pick(inputs)) == ["fine"])
    }

    @Test func watchedFilmsAreNeverPicked() {
        let inputs = WatchlistPickInputs(
            recentFilms: [film("ref", rating: 9)],
            similar: ["ref": ["seen-slug", "seen-tmdb", "ref", "fresh"]],
            candidates: [row("seen-slug", 0), row("seen-tmdb", 1, tmdb: 555), row("ref", 2),
                         row("fresh", 3)],
            watchedSlugs: ["seen-slug"],
            watchedTMDB: [555])
        #expect(slugs(WatchlistPicker.pick(inputs)) == ["fresh"])
    }

    @Test func picksWithoutAPartnerUseTheOwnersList() {
        let inputs = WatchlistPickInputs(
            recentFilms: [film("ref", rating: 10)],
            similar: ["ref": ["a"]],
            candidates: [row("a", 0)],
            membership: nil)
        let picks = WatchlistPicker.pick(inputs)
        #expect(slugs(picks) == ["a"])
        #expect(picks[0].score == 1.0)                        // no bump
    }

    @Test func theRowStopsAtTheLimit() {
        let names = (0..<30).map { "c\($0)" }
        let inputs = WatchlistPickInputs(
            recentFilms: [film("ref", rating: 10)],
            similar: ["ref": names],
            candidates: names.enumerated().map { row($1, $0) })
        #expect(WatchlistPicker.pick(inputs).count == WatchlistPicker.rowTarget)
        #expect(WatchlistPicker.pick(inputs, limit: 5).count == 5)
    }

    /// Director-only matching is an anti-goal: one prolific director must not fill the row. The
    /// director tier takes at most a third of the row; its overflow waits behind the looser tiers.
    @Test func theDirectorTierTakesAtMostAThirdOfTheRow() {
        let directors = (0..<10).map { "d\($0)" }
        let loose = (0..<3).map { "l\($0)" }
        let genre = (0..<2).map { "g\($0)" }
        var candidates: [WatchlistEntry] = []
        for slug in directors + loose { candidates.append(row(slug, candidates.count)) }
        for slug in genre { candidates.append(row(slug, candidates.count, tmdb: .some(900 + candidates.count))) }
        let inputs = WatchlistPickInputs(
            recentFilms: [film("ref", year: 2000, rating: 9)],
            similar: ["ref": ["hop"]],
            secondHop: ["hop": loose],
            directorFilms: ["ref": directors],
            referenceGenres: ["ref": ["Drama"]],
            candidates: candidates,
            candidateGenres: Dictionary(uniqueKeysWithValues: candidates.suffix(2).map { ($0.tmdbID!, ["drama"]) }))

        let cap = WatchlistPicker.rowTarget / 3
        let picks = WatchlistPicker.pick(inputs)
        #expect(slugs(picks) == Array(directors.prefix(cap)) + loose + genre + Array(directors.dropFirst(cap)))
        #expect(picks.prefix(cap).allSatisfy { $0.tier == .director })

        // A shorter row caps by its own length.
        let short = WatchlistPicker.pick(inputs, limit: 9)
        #expect(slugs(short) == ["d0", "d1", "d2"] + loose + genre + ["d3"])
    }

    @Test func eligibilityIsOneRuleForEveryCaller() {
        let unmatched = WatchlistEntry(slug: "unmatched", name: "unmatched (2000)", year: 2000,
                                       position: 0, tmdbID: nil, resolvedAt: Date())
        let candidates = [unmatched, row("removed", 1, removed: true), row("seen-slug", 2),
                          row("seen-tmdb", 3, tmdb: 555), row("ref", 4), row("fresh", 5)]
        let eligible = WatchlistPicker.eligible(candidates, watchedSlugs: ["seen-slug"],
                                                watchedTMDB: [555],
                                                references: [film("ref", rating: 9)])
        #expect(eligible.map(\.slug) == ["fresh"])
    }

    @Test func withNothingToGoOnItPicksNothing() {
        let inputs = WatchlistPickInputs(recentFilms: [], candidates: [row("a", 0)])
        #expect(WatchlistPicker.pick(inputs).isEmpty)
    }
}
