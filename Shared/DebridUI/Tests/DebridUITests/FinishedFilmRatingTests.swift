import Testing
import Foundation
@testable import DebridUI
@testable import DebridCore

private actor RecordingRelay: LetterboxdRelaying {
    private(set) var writes: [LetterboxdWrite] = []
    func send(_ write: LetterboxdWrite) async throws { writes.append(write) }
    var last: LetterboxdWrite? { writes.last }
}

private final class FakeRatings: WatchRatingProviding, @unchecked Sendable {
    var stored: [String: Int?] = [:]
    /// Every call, including the ones that write nil — telling "wrote nil" from "did not write"
    /// is the entire point of the dismiss test below.
    var writes: [(key: String, value: Int?)] = []

    func rating(forContentKey key: String) async -> Int? { stored[key] ?? nil }
    func setRating(_ value: Int?, forContentKey key: String) async {
        stored[key] = value
        writes.append((key, value))
    }
}

/// Answering the prompt that appears when the credits roll. Two destinations, and they are not
/// interchangeable: the local store is the source of truth the title page reads, and the held
/// diary entry is the mirror.
@MainActor
@Suite struct FinishedFilmRatingTests {
    private func make(_ ratings: FakeRatings,
                      _ relay: RecordingRelay) -> (FinishedFilmRating, LetterboxdPushCoordinator) {
        let push = LetterboxdPushCoordinator(outbox: InMemoryLetterboxdOutbox(), relay: relay,
                                             loggedElsewhere: { _ in false },
                                             isEnabled: { true }, ratingHold: 60)
        return (FinishedFilmRating(local: ratings, push: push), push)
    }

    @Test func ratingLandsLocallyAndOnTheDiaryEntry() async throws {
        let ratings = FakeRatings()
        let relay = RecordingRelay()
        let (rating, push) = make(ratings, relay)
        await push.recordFinish(contentKey: "movie:tmdb:73", rating: nil, plays: 1, at: Date())

        await rating.rate(8, contentKey: "movie:tmdb:73", tmdbID: 73)
        await push.waitForPendingSend()

        #expect(ratings.stored["movie:tmdb:73"] == 8)
        #expect(await relay.last?.rating == 8)
    }

    /// 🚨 Dismissing must not write anything locally. Writing nil would clear a rating the viewer
    /// had already given the film on the title page — silently destroying their own data because
    /// they ignored a prompt during the credits.
    @Test func dismissingWritesNothingLocally() async throws {
        let ratings = FakeRatings()
        ratings.stored["movie:tmdb:73"] = 7
        let relay = RecordingRelay()
        let (rating, push) = make(ratings, relay)
        await push.recordFinish(contentKey: "movie:tmdb:73", rating: 7, plays: 1, at: Date())

        await rating.dismiss(tmdbID: 73)
        await push.waitForPendingSend()

        #expect(ratings.writes.isEmpty)
        #expect(ratings.stored["movie:tmdb:73"] == 7)
        #expect(await relay.last?.rating == 7)      // the entry still carries it
    }

    /// Clearing IS a deliberate answer, unlike dismissing, and has to reach both.
    @Test func clearingARatingIsWrittenThrough() async throws {
        let ratings = FakeRatings()
        ratings.stored["movie:tmdb:73"] = 7
        let relay = RecordingRelay()
        let (rating, push) = make(ratings, relay)
        await push.recordFinish(contentKey: "movie:tmdb:73", rating: 7, plays: 1, at: Date())

        await rating.rate(nil, contentKey: "movie:tmdb:73", tmdbID: 73)
        await push.waitForPendingSend()

        #expect(ratings.writes.count == 1)
        #expect(ratings.stored["movie:tmdb:73"] == Int?.none)
        #expect(await relay.last?.rating == nil)
    }

    /// With no server configured there is no coordinator at all, and the rating still has to be
    /// kept — the local store is the source of truth, not a cache of Letterboxd.
    @Test func aRatingIsKeptEvenWithNoServerToMirrorItTo() async throws {
        let ratings = FakeRatings()
        let rating = FinishedFilmRating(local: ratings, push: nil)

        await rating.rate(6, contentKey: "movie:tmdb:73", tmdbID: 73)

        #expect(ratings.stored["movie:tmdb:73"] == 6)
    }
}
