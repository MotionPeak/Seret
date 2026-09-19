import Testing
import Foundation
@testable import DebridUI
@testable import DebridCore

private func entry(_ slug: String, tmdbID: Int?, poster: String? = "/p.jpg",
                   removed: Bool = false) -> WatchlistEntry {
    WatchlistEntry(slug: slug, name: "\(slug) (1994)", year: 1994, position: 0,
                   tmdbID: tmdbID, posterPath: poster, resolvedAt: Date(),
                   removedAt: removed ? Date() : nil)
}

/// Deterministic, so a spin's outcome is a fact a test can assert rather than something to
/// re-run until it looks right.
private struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(_ seed: UInt64) { state = seed &* 2_862_933_555_777_941_757 &+ 3_037_000_493 }
    mutating func next() -> UInt64 {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return state
    }
}

@Suite struct WatchlistRandomizerTests {

    @Test func picksOnlyFromFilmsThatCanActuallyBeOpened() {
        let entries = [entry("matched", tmdbID: 1),
                       entry("unmatched", tmdbID: nil, poster: nil),
                       entry("gone", tmdbID: 2, removed: true)]
        var rng = SeededRNG(1)
        for _ in 0..<50 {
            let spin = WatchlistRandomizer.spin(over: entries, using: &rng)
            #expect(spin?.winner.slug == "matched")
        }
    }

    @Test func nothingToSpinOverGivesNoSpin() {
        var rng = SeededRNG(2)
        #expect(WatchlistRandomizer.spin(over: [], using: &rng) == nil)
        #expect(WatchlistRandomizer.spin(over: [entry("u", tmdbID: nil, poster: nil)],
                                         using: &rng) == nil)
    }

    /// The reel is presentation; the winner is the fact. It must be the last thing the reel
    /// shows, or the animation would land on one film and the screen would name another.
    @Test func theReelEndsOnTheWinner() {
        let entries = (0..<8).map { entry("f\($0)", tmdbID: $0 + 1) }
        var rng = SeededRNG(3)
        let spin = WatchlistRandomizer.spin(over: entries, using: &rng)
        let unwrapped = try! #require(spin)
        #expect(unwrapped.reel.last?.slug == unwrapped.winner.slug)
        #expect(unwrapped.reel.count > 1)
    }

    /// Every frame the reel shows has artwork. A spin that flickers through grey placeholders
    /// looks broken rather than exciting.
    @Test func everyReelFrameHasAPoster() {
        let entries = (0..<6).map { entry("f\($0)", tmdbID: $0 + 1) }
                    + [entry("unmatched", tmdbID: nil, poster: nil)]
        var rng = SeededRNG(4)
        let spin = try! #require(WatchlistRandomizer.spin(over: entries, using: &rng))
        #expect(spin.reel.allSatisfy { $0.posterPath?.isEmpty == false })
    }

    /// A one-film watchlist still spins — it just always knows the answer.
    @Test func aSingleEligibleFilmStillProducesASpin() {
        var rng = SeededRNG(5)
        let spin = try! #require(WatchlistRandomizer.spin(over: [entry("only", tmdbID: 7)],
                                                          using: &rng))
        #expect(spin.winner.slug == "only")
        #expect(spin.reel.allSatisfy { $0.slug == "only" })
    }

    /// Consecutive duplicates would read as the reel having stalled.
    @Test func theReelNeverShowsTheSameFilmTwiceInARow() {
        let entries = (0..<5).map { entry("f\($0)", tmdbID: $0 + 1) }
        for seed in UInt64(1)...25 {
            var rng = SeededRNG(seed)
            let spin = try! #require(WatchlistRandomizer.spin(over: entries, using: &rng))
            let repeats = zip(spin.reel, spin.reel.dropFirst()).filter { $0.slug == $1.slug }
            #expect(repeats.isEmpty)
        }
    }

    @Test func differentSeedsCanReachDifferentWinners() {
        let entries = (0..<10).map { entry("f\($0)", tmdbID: $0 + 1) }
        var winners: Set<String> = []
        for seed in UInt64(1)...40 {
            var rng = SeededRNG(seed)
            if let spin = WatchlistRandomizer.spin(over: entries, using: &rng) {
                winners.insert(spin.winner.slug)
            }
        }
        #expect(winners.count > 1)
    }
}
