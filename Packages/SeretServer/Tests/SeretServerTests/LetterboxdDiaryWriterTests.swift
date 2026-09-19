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

/// Records what the writer asked the browser to do, and replies as the page would.
///
/// One evaluate does the whole write now: the page fetches its own token and uid, then posts. The
/// readiness probe `navigate` uses is not one of the writer's evaluates, so it neither counts nor
/// is recorded — the page is simply always there.
private final class ScriptedTransport: CDPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var navigations: [String] = []
    private var evaluations: [String] = []
    let postValue: [String: any Sendable]

    init(postValue: [String: any Sendable]) { self.postValue = postValue }

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
        return ["result": ["value": postValue] as [String: any Sendable]]
    }
}

@Suite struct LetterboxdDiaryWriterTests {
    fileprivate func writer(_ transport: ScriptedTransport, slugs: [Int: String] = [550: "fight-club"])
    -> LetterboxdDiaryWriter {
        LetterboxdDiaryWriter(chrome: ChromeSession(transport: transport),
                              resolver: FakeResolver(slugs: slugs))
    }

    fileprivate func ok() -> [String: any Sendable] { ["status": 200, "body": "{}"] }

    @Test func navigatesToTheFilmPageFirst() async throws {
        let t = ScriptedTransport(postValue: ok())
        try await writer(t).write(LetterboxdWrite(tmdbID: 550, rating: 8,
                                                  watchedAt: Date(), rewatch: true))
        #expect(t.navigatedTo == "https://letterboxd.com/film/fight-club/")
    }

    /// The write is a JSON API call, not a form post. `/s/save-diary-entry` still appears as the
    /// form's `action` on the live page and 404s on every shape of request — measured — so an
    /// expression that mentions it is aimed at an endpoint that no longer exists.
    @Test func thePostGoesToTheLogEntriesApi() async throws {
        let t = ScriptedTransport(postValue: ok())
        try await writer(t).write(
            LetterboxdWrite(tmdbID: 550, rating: 8,
                            watchedAt: Date(timeIntervalSince1970: 1_700_000_000), rewatch: true))
        let post = try #require(t.expressions.last)
        #expect(post.contains("/api/v0/production-log-entries"))
        #expect(post.contains("X-CSRF-TOKEN"))
        #expect(!post.contains("/s/save-diary-entry"))
    }

    /// The film's id comes from the page, never from here: guessing it would write onto another
    /// film. The token comes with it, so there is no second read to get out of step.
    ///
    /// It has to be the LID. The API rejects the uid outright - "Object not found due to error for
    /// ID: film:51977" - and accepts `2bdo`, measured against the live endpoint.
    @Test func theProductionAndTokenBothComeFromThePage() async throws {
        let t = ScriptedTransport(postValue: ok())
        try await writer(t).write(LetterboxdWrite(tmdbID: 550, rating: 8, watchedAt: Date()))
        let post = try #require(t.expressions.last)
        #expect(post.contains("/film/fight-club/json/"))
        #expect(post.contains("productionId"))
        #expect(post.contains("meta.lid"))
        #expect(!post.contains("meta.uid"))
        #expect(post.contains("meta.csrf"))
    }

    @Test func theBodyCarriesTheHalvedRatingAndTheDate() async throws {
        let t = ScriptedTransport(postValue: ok())
        try await writer(t).write(
            LetterboxdWrite(tmdbID: 550, rating: 8,
                            watchedAt: Date(timeIntervalSince1970: 1_700_000_000), rewatch: true))
        let post = try #require(t.expressions.last)
        #expect(post.contains("\"rating\":4"))
        #expect(post.contains("diaryDetails"))
        #expect(post.contains("\"rewatch\":true"))
    }

    /// A film Letterboxd does not know cannot be written, and retrying will not help.
    @Test func anUnknownFilmIsFilmNotFound() async {
        let t = ScriptedTransport(postValue: ok())
        await #expect(throws: LetterboxdError.filmNotFound) {
            try await writer(t, slugs: [:]).write(LetterboxdWrite(tmdbID: 99, rating: nil))
        }
    }

    /// The page handing back no token and no uid means it did not load as a signed-in member.
    @Test func aPageWithoutSessionMetadataIsNotAuthenticated() async {
        let t = ScriptedTransport(postValue: ["status": 0, "body": "no session metadata"])
        await #expect(throws: LetterboxdError.notAuthenticated) {
            try await writer(t).write(LetterboxdWrite(tmdbID: 550, rating: nil))
        }
    }

    @Test func aChallengedPostIsChallenged() async {
        let t = ScriptedTransport(postValue: ["status": 403, "body": "Just a moment..."])
        await #expect(throws: LetterboxdError.challenged) {
            try await writer(t).write(LetterboxdWrite(tmdbID: 550, rating: nil))
        }
    }

    /// A rejected token is worth retrying with a freshly loaded page; a dead session is not. They
    /// arrive as the same status, so the body is what separates them.
    @Test func aRejectedTokenIsTransient() async {
        let t = ScriptedTransport(postValue: ["status": 403, "body": "Invalid CSRF token"])
        await #expect(throws: LetterboxdError.transient("Letterboxd rejected the page's CSRF token")) {
            try await writer(t).write(LetterboxdWrite(tmdbID: 550, rating: nil))
        }
    }

    @Test func aPlain403IsNotAuthenticated() async {
        let t = ScriptedTransport(postValue: ["status": 403, "body": "nope"])
        await #expect(throws: LetterboxdError.notAuthenticated) {
            try await writer(t).write(LetterboxdWrite(tmdbID: 550, rating: nil))
        }
    }

    @Test func aServerErrorIsTransient() async {
        let t = ScriptedTransport(postValue: ["status": 502, "body": ""])
        await #expect(throws: LetterboxdError.transient("production-log-entries returned 502")) {
            try await writer(t).write(LetterboxdWrite(tmdbID: 550, rating: nil))
        }
    }
}
