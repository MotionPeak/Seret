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
    private var calls: [(id: Int, inWatchlist: Bool)] = []
    var failure: (any Error)?

    init(failure: (any Error)? = nil) { self.failure = failure }
    var posted: [Int] { lock.withLock { calls.map(\.id) } }
    /// What each call asked Letterboxd for. An add and a removal are the same endpoint and differ
    /// only here, so a test that ignored it could not tell them apart.
    var states: [Bool] { lock.withLock { calls.map(\.inWatchlist) } }

    func post(_ address: String, _ tmdbID: Int, _ inWatchlist: Bool) throws {
        if let failure { throw failure }
        lock.withLock { calls.append((tmdbID, inWatchlist)) }
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

@Suite struct WatchlistPushRelayTests {

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
                       serverURL: String = "http://nas:8080") -> WatchlistPushRelay {
        WatchlistPushRelay(syncer: syncer,
                           settings: { LetterboxdSettings(username: "u", isEnabled: true,
                                                          serverURL: serverURL) },
                           post: { address, id, inWatchlist in
                               try spy.post(address, id, inWatchlist)
                           })
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

    /// Every failure used to read "Couldn't reach your Seret server" — including a server that
    /// answered perfectly well with a 404 or a 500. That sent the owner to check the network when
    /// the fault was the server, and it is exactly what happened when ATS silently blocked the
    /// cleartext request: the message was technically true and diagnostically useless.
    @Test func aBadStatusBlamesTheServerNotTheNetwork() async throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let syncer = try await seededSyncer(url)
        _ = await syncer.remove(slug: "fight-club")

        let spy = PostSpy(failure: HTTPError.status(code: 404, body: ""))
        let outcome = await relay(syncer, spy).drain()
        let message = try #require(outcome.firstError)
        #expect(message.contains("404"))
        #expect(!message.contains("reach"))
    }

    /// A blocked cleartext request is not an unreachable server, and saying so is the difference
    /// between checking the Info.plist and power-cycling the NAS.
    @Test func aBlockedCleartextRequestSaysItWasBlocked() async throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let syncer = try await seededSyncer(url)
        _ = await syncer.remove(slug: "fight-club")

        let blocked = URLError(.appTransportSecurityRequiresSecureConnection)
        let spy = PostSpy(failure: HTTPError.transport(String(describing: blocked)))
        let outcome = await relay(syncer, spy).drain()
        #expect(outcome.firstError?.lowercased().contains("blocked") == true)
    }

    /// A genuine transport failure still reads as one.
    @Test func anUnreachableServerStillSaysSo() async throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let syncer = try await seededSyncer(url)
        _ = await syncer.remove(slug: "fight-club")

        let spy = PostSpy(failure: HTTPError.transport("Could not connect to the server"))
        let outcome = await relay(syncer, spy).drain()
        #expect(outcome.firstError?.contains("reach") == true)
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

    // MARK: - Adds

    @Test func pushesAPendingAddAndMarksIt() async throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let syncer = try await seededSyncer(url)
        _ = await syncer.add(tmdbID: 949, title: "Heat", year: 1995, posterPath: nil)

        let spy = PostSpy()
        let outcome = await relay(syncer, spy).drain()

        #expect(spy.posted == [949])
        #expect(spy.states == [true])
        #expect(outcome == .init(pushed: 1, failed: 0))
        #expect(await syncer.pendingAdds().isEmpty)
    }

    @Test func aPushedAddIsNotPushedAgain() async throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let syncer = try await seededSyncer(url)
        _ = await syncer.add(tmdbID: 949, title: "Heat", year: 1995, posterPath: nil)

        let spy = PostSpy()
        _ = await relay(syncer, spy).drain()
        _ = await relay(syncer, spy).drain()
        #expect(spy.posted == [949])
    }

    @Test func aFailedAddStaysPendingAndIsRetried() async throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let syncer = try await seededSyncer(url)
        _ = await syncer.add(tmdbID: 949, title: "Heat", year: 1995, posterPath: nil)

        let spy = PostSpy(failure: LetterboxdError.challenged)
        let failedOutcome = await relay(syncer, spy).drain()
        #expect(failedOutcome.failed == 1)
        #expect(failedOutcome.firstError?.contains("Cloudflare") == true)
        #expect(await syncer.pendingAdds().count == 1)

        spy.failure = nil
        #expect(await relay(syncer, spy).drain().pushed == 1)
    }

    /// Both directions drain together, and each is sent as what it is. One shared endpoint that
    /// carried the wrong boolean would silently undo the owner's other change.
    @Test func anAddAndARemovalGoOutAsOppositeStates() async throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let syncer = try await seededSyncer(url)
        _ = await syncer.remove(slug: "fight-club")
        _ = await syncer.add(tmdbID: 949, title: "Heat", year: 1995, posterPath: nil)

        let spy = PostSpy()
        let outcome = await relay(syncer, spy).drain()

        #expect(outcome.pushed == 2)
        #expect(Set(zip(spy.posted, spy.states).map { "\($0)-\($1)" }) == ["949-true", "550-false"])
        #expect(await syncer.pendingAdds().isEmpty)
        #expect(await syncer.pendingRemovals().isEmpty)
    }

    /// Nothing reached Letterboxd, so the add and the removal cancel and there is nothing to send.
    @Test func anAddTakenBackBeforeDrainingSendsNothing() async throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let syncer = try await seededSyncer(url)
        _ = await syncer.add(tmdbID: 949, title: "Heat", year: 1995, posterPath: nil)
        _ = await syncer.remove(slug: WatchlistEntry.localSlug(forTMDB: 949))

        let spy = PostSpy()
        #expect(await relay(syncer, spy).drain() == .idle)
        #expect(spy.posted.isEmpty)
    }

    @Test func withNoServerAnAddIsKeptPending() async throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let syncer = try await seededSyncer(url)
        _ = await syncer.add(tmdbID: 949, title: "Heat", year: 1995, posterPath: nil)

        let spy = PostSpy()
        #expect(await relay(syncer, spy, serverURL: "   ").drain() == .idle)
        #expect(spy.posted.isEmpty)
        #expect(await syncer.pendingAdds().count == 1)
    }
}
