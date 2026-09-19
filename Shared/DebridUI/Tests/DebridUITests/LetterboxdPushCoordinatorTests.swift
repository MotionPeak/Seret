import Testing
import Foundation
@testable import DebridUI
@testable import DebridCore

/// Records what reached the server, and fails on command.
private actor FakeRelay: LetterboxdRelaying {
    private var writes: [LetterboxdWrite] = []
    private let failure: LetterboxdError?

    init(failing: LetterboxdError? = nil) { self.failure = failing }

    func send(_ write: LetterboxdWrite) async throws {
        writes.append(write)
        if let failure { throw failure }
    }

    var count: Int { writes.count }
    var last: LetterboxdWrite? { writes.last }
}

/// A relay that blocks until it is released, so "did the caller wait for it?" is answerable.
private actor HangingRelay: LetterboxdRelaying {
    private var released = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private(set) var started = 0

    func send(_ write: LetterboxdWrite) async throws {
        started += 1
        if released { return }
        await withCheckedContinuation { waiting.append($0) }
    }

    func release() {
        released = true
        waiting.forEach { $0.resume() }
        waiting.removeAll()
    }
}

@Suite struct LetterboxdPushCoordinatorTests {
    private func coordinator(relay: FakeRelay,
                             outbox: any LetterboxdOutbox = InMemoryLetterboxdOutbox(),
                             logged: Set<Int> = []) -> LetterboxdPushCoordinator {
        LetterboxdPushCoordinator(outbox: outbox, relay: relay,
                                  loggedElsewhere: { logged.contains($0) },
                                  isEnabled: { true })
    }

    @Test func aFinishedFilmIsQueuedAndSent() async throws {
        let relay = FakeRelay()
        let push = coordinator(relay: relay)
        await push.recordFinish(contentKey: "movie:tmdb:73", rating: 9, plays: 1, at: Date())
        await push.waitForPendingSend()

        #expect(await relay.count == 1)
        #expect(await relay.last?.tmdbID == 73)
        #expect(await relay.last?.rating == 9)
    }

    /// Letterboxd has no television, and a parsed-title key is not a TMDB id. Neither can be
    /// written, and neither should sit in the queue being retried forever.
    @Test func onlyFilmsWithATmdbIdAreQueued() async throws {
        let relay = FakeRelay()
        let push = coordinator(relay: relay)
        await push.recordFinish(contentKey: "show:tmdb:1396:s1e2", rating: nil, plays: 1, at: Date())
        await push.recordFinish(contentKey: "movie:speed:1994", rating: nil, plays: 1, at: Date())
        await push.waitForPendingSend()
        #expect(await relay.count == 0)
    }

    @Test func aSecondPlayIsARewatch() async throws {
        let relay = FakeRelay()
        let push = coordinator(relay: relay)
        await push.recordFinish(contentKey: "movie:tmdb:73", rating: nil, plays: 2, at: Date())
        await push.waitForPendingSend()
        #expect(await relay.last?.rewatch == true)
    }

    /// The signal Seret cannot produce: logged on Letterboxd years ago, watched here for the first
    /// time. The local play count is 1 and it is still a rewatch.
    @Test func aFilmAlreadyLoggedThereIsARewatchOnItsFirstLocalPlay() async throws {
        let relay = FakeRelay()
        let push = coordinator(relay: relay, logged: [73])
        await push.recordFinish(contentKey: "movie:tmdb:73", rating: nil, plays: 1, at: Date())
        await push.waitForPendingSend()
        #expect(await relay.last?.rewatch == true)
    }

    @Test func aFirstViewingIsNotARewatch() async throws {
        let relay = FakeRelay()
        let push = coordinator(relay: relay)
        await push.recordFinish(contentKey: "movie:tmdb:73", rating: nil, plays: 1, at: Date())
        await push.waitForPendingSend()
        #expect(await relay.last?.rewatch == false)
    }

    /// A failed send keeps the write. Losing it would mean the diary silently missing a film.
    @Test func aFailedSendLeavesTheWriteQueued() async throws {
        let outbox = InMemoryLetterboxdOutbox()
        let push = coordinator(relay: FakeRelay(failing: .notAuthenticated), outbox: outbox)
        await push.recordFinish(contentKey: "movie:tmdb:73", rating: nil, plays: 1, at: Date())
        await push.waitForPendingSend()

        #expect(try await outbox.all().count == 1)
        let status = await push.status()
        #expect(status.pending == 1)
        // In the owner's terms, not the enum's. "notAuthenticated" on a television explains
        // nothing and suggests nothing — and a screenshot is what caught it, not this test.
        let message = try #require(status.lastError)
        #expect(message.contains("signed us out"))
        #expect(!message.contains("notAuthenticated"))
    }

    /// Retrying a film Letterboxd does not have cannot ever work, so it is dropped rather than
    /// blocking everything behind it.
    @Test func anUnknownFilmIsDroppedRatherThanRetriedForever() async throws {
        let outbox = InMemoryLetterboxdOutbox()
        let push = coordinator(relay: FakeRelay(failing: .filmNotFound), outbox: outbox)
        await push.recordFinish(contentKey: "movie:tmdb:73", rating: nil, plays: 1, at: Date())
        await push.waitForPendingSend()
        #expect(try await outbox.all().isEmpty)
    }

    @Test func nothingIsQueuedWhenTheFeatureIsOff() async throws {
        let relay = FakeRelay()
        let outbox = InMemoryLetterboxdOutbox()
        let push = LetterboxdPushCoordinator(outbox: outbox, relay: relay,
                                             loggedElsewhere: { _ in false },
                                             isEnabled: { false })
        await push.recordFinish(contentKey: "movie:tmdb:73", rating: 9, plays: 1, at: Date())
        await push.waitForPendingSend()
        #expect(await relay.count == 0)
        #expect(try await outbox.all().isEmpty)
    }

    /// A write that failed and is waiting must not be retried before its backoff has passed.
    @Test func drainRespectsTheBackoff() async throws {
        let outbox = InMemoryLetterboxdOutbox()
        let relay = FakeRelay(failing: .transient("server off"))
        let push = coordinator(relay: relay, outbox: outbox)
        let now = Date()
        await push.recordFinish(contentKey: "movie:tmdb:73", rating: nil, plays: 1, at: now)
        await push.waitForPendingSend()
        #expect(await relay.count == 1)

        await push.drain(now: now)
        #expect(await relay.count == 1)          // still inside the backoff

        await push.drain(now: now.addingTimeInterval(LetterboxdBackoff.delay(forAttempt: 1) + 1))
        #expect(await relay.count == 2)
    }

    /// 🚨 The caller is the 1s playback tick, and the send drives a browser on the Synology —
    /// nearly nine seconds, measured. The player allows one save in flight at a time, so awaiting
    /// the send here stops position-saving for the whole of it: quit in that window and the resume
    /// point is stale by however long it took.
    ///
    /// The write is on disk before this returns, so there is nothing to wait for.
    @Test func finishingDoesNotWaitForTheSend() async throws {
        let relay = HangingRelay()
        let outbox = InMemoryLetterboxdOutbox()
        let push = LetterboxdPushCoordinator(outbox: outbox, relay: relay,
                                             loggedElsewhere: { _ in false },
                                             isEnabled: { true })

        await push.recordFinish(contentKey: "movie:tmdb:73", rating: 9, plays: 1, at: Date())

        // Returned while the send is still in flight, and the write is already durable.
        #expect(try await outbox.all().count == 1)
        await relay.release()
        await push.waitForPendingSend()
        #expect(try await outbox.all().isEmpty)
    }

    /// A browser that needs a human stops the whole drain. Marching the rest of the queue into the
    /// same wall only inflates every backoff, so the films behind it wait hours for no reason.
    @Test func aSignedOutBrowserStopsTheDrainRatherThanBurningTheQueue() async throws {
        let outbox = InMemoryLetterboxdOutbox()
        let now = Date()
        try await outbox.enqueue(LetterboxdWrite(tmdbID: 73, rating: nil, watchedAt: now))
        try await outbox.enqueue(LetterboxdWrite(tmdbID: 550, rating: nil, watchedAt: now))

        let relay = FakeRelay(failing: .notAuthenticated)
        await coordinator(relay: relay, outbox: outbox).drain(now: now)

        #expect(await relay.count == 1)
        let stored = try await outbox.all()
        #expect(stored.count == 2)
        #expect(stored.first(where: { $0.tmdbID == 550 })?.attempts == 0)
    }
}
