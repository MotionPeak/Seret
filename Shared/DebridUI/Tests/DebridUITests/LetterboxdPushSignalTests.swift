import Testing
import Foundation
@testable import DebridUI
@testable import DebridCore

private actor FailingRelay: LetterboxdRelaying {
    private let error: LetterboxdError
    init(_ error: LetterboxdError) { self.error = error }
    func send(_ write: LetterboxdWrite) async throws { throw error }
}

private actor SucceedingRelay: LetterboxdRelaying {
    func send(_ write: LetterboxdWrite) async throws {}
}

@MainActor
@Suite struct LetterboxdPushSignalTests {
    private func push(relay: any LetterboxdRelaying,
                      signal: LetterboxdPushSignal) -> LetterboxdPushCoordinator {
        // No hold: these are about the signal a LANDED entry raises. The couple of minutes a new
        // entry waits for a rating is `LetterboxdRatingHoldTests`' subject, not this suite's.
        LetterboxdPushCoordinator(outbox: InMemoryLetterboxdOutbox(), relay: relay,
                                  loggedElsewhere: { _ in false },
                                  isEnabled: { true },
                                  signal: signal, ratingHold: 0)
    }

    @Test func aLandedEntryNamesTheFilmItLogged() async throws {
        let signal = LetterboxdPushSignal()
        let coordinator = push(relay: SucceedingRelay(), signal: signal)

        await coordinator.recordFinish(contentKey: "movie:tmdb:73", rating: 9, plays: 1, at: Date())
        await coordinator.waitForPendingSend()

        #expect(signal.lastLogged == 73)
    }

    /// Silent on failure, on purpose. Nothing about a dead browser is actionable while a film is
    /// playing, and Settings already carries it — interrupting the film to say so is worse.
    @Test func aFailedSendSaysNothing() async throws {
        let signal = LetterboxdPushSignal()
        let coordinator = push(relay: FailingRelay(.notAuthenticated), signal: signal)

        await coordinator.recordFinish(contentKey: "movie:tmdb:73", rating: 9, plays: 1, at: Date())
        await coordinator.waitForPendingSend()

        #expect(signal.lastLogged == nil)
    }

    /// The same film logged twice must be able to show twice — a rewatch is a real second entry.
    /// A view watching `lastLogged` alone would see no change and stay silent.
    @Test func loggingTheSameFilmAgainIsANewEvent() async throws {
        let signal = LetterboxdPushSignal()
        let coordinator = push(relay: SucceedingRelay(), signal: signal)

        await coordinator.recordFinish(contentKey: "movie:tmdb:73", rating: 9, plays: 1, at: Date())
        await coordinator.waitForPendingSend()
        let first = signal.event

        await coordinator.recordFinish(contentKey: "movie:tmdb:73", rating: 9, plays: 2, at: Date())
        await coordinator.waitForPendingSend()

        #expect(signal.lastLogged == 73)
        #expect(signal.event != first)
    }
}
