import Testing
import Foundation
@testable import DebridUI
@testable import DebridCore

private func tempURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("relay-\(UUID().uuidString).json")
}

/// Records what the relay tried to post, and can be told to fail.
private final class PostSpy: @unchecked Sendable {
    private let lock = NSLock()
    private var ids: [Int] = []
    var failure: (any Error)?

    init(failure: (any Error)? = nil) { self.failure = failure }
    var posted: [Int] { lock.withLock { ids } }

    func post(_ address: String, _ tmdbID: Int) throws {
        if let failure { throw failure }
        lock.withLock { ids.append(tmdbID) }
    }
}

private struct StubReader: LetterboxdProfileReading {
    let entries: [LetterboxdEntry]
    func films() async throws -> [LetterboxdEntry] { [] }
    func watchlist() async throws -> [LetterboxdEntry] { entries }
}

private struct StubResolver: WatchlistTitleResolving {
    func match(name: String, year: Int?) async throws -> WatchlistMatch? {
        WatchlistMatch(tmdbID: 550, posterPath: "/p.jpg")
    }
}

@Suite struct WatchlistRemovalRelayTests {

    private func seededSyncer(_ url: URL) async throws -> WatchlistSyncer {
        let syncer = WatchlistSyncer(
            reader: StubReader(entries: [LetterboxdEntry(slug: "fight-club", name: "Fight Club (1999)",
                                                         year: 1999, rating: nil)]),
            resolver: StubResolver(),
            store: WatchlistStore(fileURL: url),
            resolveDelay: .zero)
        _ = try await syncer.sync()
        return syncer
    }

    private func relay(_ syncer: WatchlistSyncer, _ spy: PostSpy,
                       serverURL: String = "http://nas:8080") -> WatchlistRemovalRelay {
        WatchlistRemovalRelay(syncer: syncer,
                              settings: { LetterboxdSettings(username: "u", isEnabled: true,
                                                             serverURL: serverURL) },
                              post: { address, id in try spy.post(address, id) })
    }

    @Test func pushesAPendingRemovalAndMarksIt() async throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let syncer = try await seededSyncer(url)
        _ = await syncer.remove(slug: "fight-club")

        let spy = PostSpy()
        let outcome = await relay(syncer, spy).drain()

        #expect(spy.posted == [550])
        #expect(outcome == .init(pushed: 1, failed: 0))
        #expect(await syncer.pendingRemovals().isEmpty)
    }

    /// Draining twice must not tell Letterboxd twice.
    @Test func aPushedRemovalIsNotPushedAgain() async throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let syncer = try await seededSyncer(url)
        _ = await syncer.remove(slug: "fight-club")

        let spy = PostSpy()
        _ = await relay(syncer, spy).drain()
        _ = await relay(syncer, spy).drain()
        #expect(spy.posted == [550])
    }

    /// A failed push stays pending — the next drain retries it. The film is gone from the screen
    /// either way, because the mirror is the local truth.
    @Test func aFailedPushStaysPendingAndIsRetried() async throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let syncer = try await seededSyncer(url)
        _ = await syncer.remove(slug: "fight-club")

        let spy = PostSpy(failure: URLError(.cannotConnectToHost))
        let failedOutcome = await relay(syncer, spy).drain()
        #expect(failedOutcome.failed == 1)
        #expect(failedOutcome.firstError?.contains("Seret server") == true)
        #expect(await syncer.pendingRemovals().count == 1)

        spy.failure = nil
        let retried = await relay(syncer, spy).drain()
        #expect(retried.pushed == 1)
        #expect(spy.posted == [550])
    }

    /// No server configured: the removal is kept pending, not dropped. The owner may simply not
    /// have set one up, and a removal they made is still a removal they want.
    @Test func withNoServerNothingIsPostedAndNothingIsLost() async throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let syncer = try await seededSyncer(url)
        _ = await syncer.remove(slug: "fight-club")

        let spy = PostSpy()
        let outcome = await relay(syncer, spy, serverURL: "   ").drain()
        #expect(outcome == .idle)
        #expect(spy.posted.isEmpty)
        #expect(await syncer.pendingRemovals().count == 1)
    }

    @Test func withNothingPendingItDoesNothing() async throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let syncer = try await seededSyncer(url)
        let spy = PostSpy()
        #expect(await relay(syncer, spy).drain() == .idle)
        #expect(spy.posted.isEmpty)
    }

    /// A signed-out browser needs a different fix from an unreachable server, so it must not read
    /// as one.
    @Test func aSignedOutBrowserSaysSoRatherThanBlamingTheNetwork() async throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let syncer = try await seededSyncer(url)
        _ = await syncer.remove(slug: "fight-club")

        let spy = PostSpy(failure: LetterboxdError.notAuthenticated)
        let outcome = await relay(syncer, spy).drain()
        #expect(outcome.firstError?.contains("signed out") == true)
    }
}
