import Testing
import Foundation
@testable import DebridCore

private func row(_ slug: String, _ position: Int, tmdb: Int? = nil,
                 removed: Bool = false) -> WatchlistEntry {
    WatchlistEntry(slug: slug, name: "\(slug) (1994)", year: 1994, position: position,
                   tmdbID: tmdb, posterPath: tmdb.map { "/\($0).jpg" }, resolvedAt: Date(),
                   removedAt: removed ? Date(timeIntervalSince1970: 100) : nil)
}

@Suite struct WatchlistMergeTests {

    @Test func withNoPartnerItIsTheOwnersListInOrder() {
        let merged = WatchlistMerge.combine(owner: [row("b", 1), row("a", 0)], partner: [])
        #expect(merged.map(\.slug) == ["a", "b"])
        #expect(merged.map(\.position) == [0, 1])
    }

    /// Each list's newest first, alternating — neither person's list is buried under the other's.
    @Test func theListsInterleaveByPositionWithTiesToTheOwner() {
        let merged = WatchlistMerge.combine(owner: [row("a", 0), row("b", 1)],
                                            partner: [row("c", 0), row("d", 1)])
        #expect(merged.map(\.slug) == ["a", "c", "b", "d"])
        #expect(merged.map(\.position) == [0, 1, 2, 3])
    }

    /// A film the owner added in Seret sits at a negative position, in front of everything.
    @Test func theOwnersLocalAddStaysInFront() {
        let add = WatchlistEntry.locallyAdded(tmdbID: 9, title: "New", year: 2026,
                                              posterPath: nil, position: -1)
        let merged = WatchlistMerge.combine(owner: [add, row("a", 0)], partner: [row("c", 0)])
        #expect(merged.first?.slug == "tmdb-9")
    }

    @Test func aFilmOnBothListsAppearsOnceAsTheOwnersRow() {
        var mine = row("speed", 3, tmdb: 1637)
        mine.addedLocallyAt = nil
        let merged = WatchlistMerge.combine(owner: [mine], partner: [row("speed", 0, tmdb: 1637)])
        #expect(merged.count == 1)
        #expect(merged.first?.slug == "speed")
    }

    /// The owner's own add carries a placeholder slug, so only the TMDB id can say it is the same
    /// film as the one already on the partner's list.
    @Test func aLocalAddAndACrawledRowOfTheSameFilmAreOneFilm() {
        let add = WatchlistEntry.locallyAdded(tmdbID: 603, title: "The Matrix", year: 1999,
                                              posterPath: nil, position: -1)
        let merged = WatchlistMerge.combine(owner: [add],
                                            partner: [row("the-matrix", 0, tmdb: 603)])
        #expect(merged.count == 1)
        #expect(merged.first?.slug == "tmdb-603")
    }

    /// Visible if ANY list holding it has not hidden it.
    @Test func anOwnerHiddenFilmTheOtherListStillHoldsStaysVisible() {
        let merged = WatchlistMerge.combine(owner: [row("speed", 0, tmdb: 1, removed: true)],
                                            partner: [row("speed", 0, tmdb: 1)])
        #expect(merged.count == 1)
        #expect(merged.first?.isRemoved == false)
    }

    @Test func aFilmHiddenOnBothSidesIsOneHiddenRow() {
        let merged = WatchlistMerge.combine(owner: [row("speed", 0, tmdb: 1, removed: true)],
                                            partner: [row("speed", 0, tmdb: 1, removed: true)])
        #expect(merged.count == 1)
        #expect(merged.first?.isRemoved == true)
    }

    /// Nothing ever pushes a partner's row, so it must never read as pending — otherwise the
    /// toggle would treat re-adding a film hidden here as cancelling a write that never existed.
    @Test func aPartnersHiddenRowIsNeverPending() {
        let merged = WatchlistMerge.combine(owner: [],
                                            partner: [row("speed", 0, tmdb: 1, removed: true)])
        #expect(merged.first?.isRemoved == true)
        #expect(merged.first?.needsRemovalPush == false)
        #expect(merged.first?.needsAddPush == false)
    }

    @Test func membershipSaysWhichListsHoldAFilm() {
        let add = WatchlistEntry.locallyAdded(tmdbID: 603, title: "The Matrix", year: 1999,
                                              posterPath: nil, position: -1)
        let membership = WatchlistMembership(
            owner: [row("mine", 0, tmdb: 1), add],
            partner: [row("hers", 0, tmdb: 2), row("the-matrix", 1, tmdb: 603),
                      row("hidden", 2, tmdb: 4, removed: true)])

        #expect(membership.holders(of: row("mine", 0, tmdb: 1)) == .init(owner: true, partner: false))
        #expect(membership.holders(of: row("hers", 0, tmdb: 2)) == .init(owner: false, partner: true))
        #expect(membership.holders(of: add) == .init(owner: true, partner: true))
        // Hidden is still held: the wording for a removal depends on whose list it came from.
        #expect(membership.holders(of: row("hidden", 0, tmdb: 4)) == .init(owner: false, partner: true))
        #expect(WatchlistMembership.empty.holders(of: add) == .init(owner: false, partner: false))
    }
}
