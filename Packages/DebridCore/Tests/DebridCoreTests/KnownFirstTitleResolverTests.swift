import Testing
import Foundation
@testable import DebridCore

private final class FallbackCalls: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func bump() { lock.lock(); defer { lock.unlock() }; count += 1 }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}

private struct CountingResolver: WatchlistTitleResolving {
    let calls: FallbackCalls
    var answer: WatchlistMatch? = WatchlistMatch(tmdbID: 999, posterPath: "/tmdb.jpg")
    var failure: (any Error)?

    func match(name: String, year: Int?) async throws -> WatchlistMatch? {
        calls.bump()
        if let failure { throw failure }
        return answer
    }
}

private func known(_ name: String, year: Int?, tmdb: Int?) -> WatchlistEntry {
    WatchlistEntry(slug: name.lowercased(), name: name, year: year, position: 0,
                   tmdbID: tmdb, posterPath: tmdb.map { "/\($0).jpg" }, resolvedAt: Date())
}

@Suite struct KnownFirstTitleResolverTests {

    /// Letterboxd renders one film's name identically on everyone's watchlist, so a film already
    /// matched on the owner's list needs no TMDB search on the partner's.
    @Test func aFilmAlreadyMatchedIsAnsweredWithoutSearching() async throws {
        let calls = FallbackCalls()
        let resolver = KnownFirstTitleResolver(
            known: { [known("Speed (1994)", year: 1994, tmdb: 1637)] },
            fallback: CountingResolver(calls: calls))
        let match = try await resolver.match(name: "Speed (1994)", year: 1994)
        #expect(match == WatchlistMatch(tmdbID: 1637, posterPath: "/1637.jpg"))
        #expect(calls.value == 0)
    }

    @Test func anUnknownFilmIsSearched() async throws {
        let calls = FallbackCalls()
        let resolver = KnownFirstTitleResolver(known: { [] }, fallback: CountingResolver(calls: calls))
        let match = try await resolver.match(name: "Heat (1995)", year: 1995)
        #expect(match?.tmdbID == 999)
        #expect(calls.value == 1)
    }

    /// A known row TMDB could not match is no answer — the partner's copy gets its own search.
    @Test func aKnownButUnmatchedFilmIsSearched() async throws {
        let calls = FallbackCalls()
        let resolver = KnownFirstTitleResolver(known: { [known("Odd (2001)", year: 2001, tmdb: nil)] },
                                               fallback: CountingResolver(calls: calls))
        _ = try await resolver.match(name: "Odd (2001)", year: 2001)
        #expect(calls.value == 1)
    }

    /// Remakes share names; the year is what tells them apart.
    @Test func aSameNamedFilmFromAnotherYearIsSearched() async throws {
        let calls = FallbackCalls()
        let resolver = KnownFirstTitleResolver(known: { [known("Dune", year: 1984, tmdb: 841)] },
                                               fallback: CountingResolver(calls: calls))
        let match = try await resolver.match(name: "Dune", year: 2021)
        #expect(match?.tmdbID == 999)
        #expect(calls.value == 1)
    }

    /// A failed search must stay a failure — the syncer retries only what threw.
    @Test func aFailedSearchStillThrows() async {
        let resolver = KnownFirstTitleResolver(
            known: { [] },
            fallback: CountingResolver(calls: FallbackCalls(), failure: LetterboxdError.transient("x")))
        await #expect(throws: LetterboxdError.self) {
            _ = try await resolver.match(name: "Heat (1995)", year: 1995)
        }
    }
}
