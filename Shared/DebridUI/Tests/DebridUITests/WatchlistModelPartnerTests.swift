import Testing
import Foundation
@testable import DebridUI
@testable import DebridCore

private func film(_ slug: String, tmdb: Int) -> WatchlistEntry {
    WatchlistEntry(slug: slug, name: "\(slug.capitalized) (1994)", year: 1994, position: 0,
                   tmdbID: tmdb, posterPath: "/\(tmdb).jpg", resolvedAt: Date())
}

private let mine = film("speed", tmdb: 1)
private let hers = film("heat", tmdb: 2)
private let ours = film("dune", tmdb: 3)

private func withNoga(partnerError: String? = nil) -> WatchlistCombinedStatus {
    WatchlistCombinedStatus(membership: WatchlistMembership(owner: [mine, ours], partner: [hers, ours]),
                            partnerName: "Noga", partnerError: partnerError)
}

private let settings = LetterboxdSettings(username: "thebigshin", isEnabled: true,
                                          partnerUsername: "nogap", partnerName: "Noga")

@MainActor
@Suite struct WatchlistModelPartnerTests {

    /// A private or renamed partner profile is a footnote, not an error over the owner's list.
    @Test func aPartnerFailureIsASecondaryLineNotAFailedScreen() async {
        let model = WatchlistModel(cached: [], settings: settings,
                                   status: { withNoga(partnerError: "Couldn't read Noga's watchlist.") }) { _ in
            [mine]
        }
        await model.syncNow()
        #expect(model.phase == .idle)
        #expect(model.entries.map(\.slug) == ["speed"])
        #expect(model.partnerMessage == "Couldn't read Noga's watchlist.")
    }

    @Test func aHealthyPartnerSaysNothing() async {
        let model = WatchlistModel(cached: [], settings: settings, status: { withNoga() }) { _ in [mine] }
        await model.syncNow()
        #expect(model.partnerMessage == nil)
    }

    /// The status is read when the screen opens, not only after a crawl — a crawl is skipped when
    /// the list is fresh, and the screen still has to word a removal correctly.
    @Test func openingAFreshScreenStillReadsTheStatus() async {
        let model = WatchlistModel(cached: [hers],
                                   settings: LetterboxdSettings(username: "thebigshin", lastImportAt: Date(),
                                                                partnerUsername: "nogap"),
                                   status: { withNoga() }) { _ in [] }
        await model.syncIfStale()
        #expect(model.removalMessage(for: hers).contains("Noga"))
    }

    @Test func removingTheOwnersFilmSaysItLeavesLetterboxd() async {
        let model = WatchlistModel(cached: [], settings: settings, status: { withNoga() }) { _ in [] }
        await model.refreshStatus()
        #expect(model.removalMessage(for: mine) == "Speed will be removed from your Letterboxd watchlist.")
    }

    /// Only the owner's account can be written to.
    @Test func removingThePartnersFilmSaysItIsOnlyHiddenHere() async {
        let model = WatchlistModel(cached: [], settings: settings, status: { withNoga() }) { _ in [] }
        await model.refreshStatus()
        #expect(model.removalMessage(for: hers)
                == "Heat will be hidden in Seret. It stays on Noga's Letterboxd watchlist.")
    }

    @Test func removingASharedFilmSaysBoth() async {
        let model = WatchlistModel(cached: [], settings: settings, status: { withNoga() }) { _ in [] }
        await model.refreshStatus()
        #expect(model.removalMessage(for: ours)
                == "Dune will be removed from your Letterboxd watchlist. It stays on Noga's, hidden here.")
    }

    @Test func withoutAPartnerTheWordingIsUnchanged() {
        let model = WatchlistModel(cached: [], settings: settings) { _ in [] }
        #expect(model.removalMessage(for: hers) == "Heat will be removed from your Letterboxd watchlist.")
        #expect(model.partnerMessage == nil)
    }

    /// The push drain can take a whole HTTP timeout when the server is unreachable, and the grid
    /// already shows the partner's films from disk — so whose list a film is on is read first.
    @Test func theStatusIsReadBeforeThePushDrain() async {
        let order = CallOrder()
        let model = WatchlistModel(cached: [hers], settings: settings,
                                   relay: { order.note("relay"); return .idle },
                                   status: { order.note("status"); return withNoga() }) { _ in [] }
        await model.syncIfStale()
        #expect(order.calls.first == "status")
    }
}

private final class CallOrder: @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [String] = []
    func note(_ call: String) { lock.withLock { _calls.append(call) } }
    var calls: [String] { lock.withLock { _calls } }
}
