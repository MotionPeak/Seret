import Testing
import Foundation
@testable import SeretServer
@testable import DebridCore

private struct FakeResolver: LetterboxdFilmResolving {
    let slugs: [Int: String]
    func slug(forTMDB id: Int) async throws -> String {
        guard let s = slugs[id] else { throw LetterboxdError.filmNotFound }
        return s
    }
}

/// Replies as the page would, and records what it was asked. Mirrors the diary writer's fake: the
/// readiness probe `navigate` uses is not one of the writer's evaluates, so it is not recorded.
private final class ScriptedTransport: CDPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var navigations: [String] = []
    private var evaluations: [String] = []
    let reply: [String: any Sendable]

    init(reply: [String: any Sendable]) { self.reply = reply }

    var navigatedTo: String? { lock.withLock { navigations.first } }
    var expressions: [String] { lock.withLock { evaluations } }

    func send(method: String, params: [String: any Sendable]) async throws -> [String: any Sendable] {
        if method == "Page.navigate" {
            lock.withLock { navigations.append((params["url"] as? String) ?? "") }
            return [:]
        }
        guard method == "Runtime.evaluate" else { return [:] }
        let expression = (params["expression"] as? String) ?? ""
        if expression.contains("document.readyState") {
            let href = lock.withLock { navigations.last ?? "" }
            return ["result": ["value": ["href": href, "ready": "complete"] as [String: any Sendable]]
                        as [String: any Sendable]]
        }
        lock.withLock { evaluations.append(expression) }
        return ["result": ["value": reply] as [String: any Sendable]]
    }
}

@Suite struct LetterboxdWatchlistWriterTests {
    private func writer(_ transport: ScriptedTransport,
                        slugs: [Int: String] = [550: "fight-club"]) -> LetterboxdWatchlistWriter {
        LetterboxdWatchlistWriter(chrome: ChromeSession(transport: transport),
                                  resolver: FakeResolver(slugs: slugs))
    }

    private func ok() -> [String: any Sendable] { ["status": 200, "body": "{}"] }

    private func removal(_ tmdbID: Int = 550) -> LetterboxdWrite {
        LetterboxdWrite(tmdbID: tmdbID, operation: .watchlist, inWatchlist: false)
    }

    @Test func navigatesToTheFilmPageFirst() async throws {
        let t = ScriptedTransport(reply: ok())
        try await writer(t).write(removal())
        #expect(t.navigatedTo == "https://letterboxd.com/film/fight-club/")
    }

    /// `PATCH /api/v0/me/watchlist/{lid}` — measured. The page's own `watchlistAction`
    /// (`/film/{slug}/add-to-watchlist/`) is a static template value and is deliberately unused.
    @Test func thePatchGoesToTheWatchlistApi() async throws {
        let t = ScriptedTransport(reply: ok())
        try await writer(t).write(removal())
        let call = try #require(t.expressions.last)
        #expect(call.contains("/api/v0/me/watchlist/"))
        #expect(call.contains("'PATCH'"))
        #expect(call.contains("X-CSRF-TOKEN"))
        #expect(!call.contains("add-to-watchlist"))
    }

    /// The LID and the token both come from the page, in one read, so they cannot get out of step.
    @Test func theFilmIdAndTokenComeFromThePage() async throws {
        let t = ScriptedTransport(reply: ok())
        try await writer(t).write(removal())
        let call = try #require(t.expressions.last)
        #expect(call.contains("/film/fight-club/json/"))
        #expect(call.contains("meta.lid"))
        #expect(call.contains("meta.csrf"))
        #expect(!call.contains("meta.uid"))
    }

    /// 🚨 `inWatchlist`, not `isInWatchlist`. The latter is the site component's own state name and
    /// the API answers it with `400 Unknown property at: isInWatchlist` — measured.
    @Test func theBodyUsesTheWirePropertyName() async throws {
        let t = ScriptedTransport(reply: ok())
        try await writer(t).write(removal())
        let call = try #require(t.expressions.last)
        #expect(call.contains(#"{"inWatchlist":false}"#))
        #expect(!call.contains("isInWatchlist"))
    }

    @Test func addingSendsTrue() async throws {
        let t = ScriptedTransport(reply: ok())
        try await writer(t).write(LetterboxdWrite(tmdbID: 550, operation: .watchlist,
                                                  inWatchlist: true))
        #expect(try #require(t.expressions.last).contains(#"{"inWatchlist":true}"#))
    }

    /// A write asking for no change is not an error, and must not reach the network.
    @Test func aWriteWithNoFlagDoesNothingAtAll() async throws {
        let t = ScriptedTransport(reply: ok())
        try await writer(t).write(LetterboxdWrite(tmdbID: 550, operation: .watchlist))
        #expect(t.navigatedTo == nil)
        #expect(t.expressions.isEmpty)
    }

    @Test func anUnknownFilmIsFilmNotFound() async {
        let t = ScriptedTransport(reply: ok())
        await #expect(throws: LetterboxdError.filmNotFound) {
            try await writer(t, slugs: [:]).write(removal(99))
        }
    }

    /// Being signed out, being challenged, and a rejected token need three different fixes, so
    /// they must not arrive as one error.
    @Test func aSignedOutPageIsNotAuthenticated() async {
        let t = ScriptedTransport(reply: ["status": 0, "body": "no session metadata"])
        await #expect(throws: LetterboxdError.notAuthenticated) { try await writer(t).write(removal()) }
    }

    @Test func aCloudflareChallengeSaysSo() async {
        let t = ScriptedTransport(reply: ["status": 403, "body": "<html>Just a moment...</html>"])
        await #expect(throws: LetterboxdError.challenged) { try await writer(t).write(removal()) }
    }

    /// A 400 names the offending property. Retrying cannot fix a contract change, so it is
    /// surfaced with the API's own words rather than queued for hours of the same answer.
    @Test func aRejectedBodyCarriesTheApisReason() async throws {
        let t = ScriptedTransport(reply: ["status": 400,
                                          "body": #"{"message":"Unknown property at: isInWatchlist"}"#])
        await #expect(throws: LetterboxdError.self) { try await writer(t).write(removal()) }
        do {
            try await writer(t).write(removal())
        } catch let LetterboxdError.transient(message) {
            #expect(message.contains("Unknown property"))
        }
    }
}
