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
/// The first evaluate reads the page; the second performs the POST.
private final class ScriptedTransport: CDPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var navigations: [String] = []
    private var evaluations: [String] = []
    let pageValue: [String: any Sendable]
    let postValue: [String: any Sendable]

    init(pageValue: [String: any Sendable], postValue: [String: any Sendable]) {
        self.pageValue = pageValue
        self.postValue = postValue
    }

    var navigatedTo: String? { lock.withLock { navigations.first } }
    var expressions: [String] { lock.withLock { evaluations } }

    func send(method: String, params: [String: any Sendable]) async throws -> [String: any Sendable] {
        if method == "Page.navigate" {
            lock.withLock { navigations.append((params["url"] as? String) ?? "") }
            return [:]
        }
        guard method == "Runtime.evaluate" else { return [:] }
        let expression = (params["expression"] as? String) ?? ""
        // `navigate` polls the document until it is loaded. That probe is not one of the writer's
        // own evaluates, so it neither counts nor gets recorded — the page is simply always there.
        if expression.contains("document.readyState") {
            let href = lock.withLock { navigations.last ?? "" }
            return ["result": ["value": ["href": href, "ready": "complete"] as [String: any Sendable]]
                        as [String: any Sendable]]
        }
        let n = lock.withLock { () -> Int in
            evaluations.append(expression)
            return evaluations.count
        }
        return ["result": ["value": n == 1 ? pageValue : postValue] as [String: any Sendable]]
    }
}

@Suite struct LetterboxdDiaryWriterTests {
    fileprivate func writer(_ transport: ScriptedTransport, slugs: [Int: String] = [550: "fight-club"])
    -> LetterboxdDiaryWriter {
        LetterboxdDiaryWriter(chrome: ChromeSession(transport: transport),
                              resolver: FakeResolver(slugs: slugs))
    }

    fileprivate func goodPage() -> [String: any Sendable] { ["csrf": "TOKEN", "uid": "film:1620206"] }
    fileprivate func goodPost() -> [String: any Sendable] { ["status": 200, "ok": true, "body": ""] }

    @Test func navigatesToTheFilmPageFirst() async throws {
        let t = ScriptedTransport(pageValue: goodPage(), postValue: goodPost())
        try await writer(t).write(LetterboxdWrite(tmdbID: 550, rating: 8,
                                                  watchedAt: Date(), rewatch: true))
        #expect(t.navigatedTo == "https://letterboxd.com/film/fight-club/")
    }

    @Test func thePostCarriesTheCapturedFields() async throws {
        let t = ScriptedTransport(pageValue: goodPage(), postValue: goodPost())
        try await writer(t).write(
            LetterboxdWrite(tmdbID: 550, rating: 8,
                            watchedAt: Date(timeIntervalSince1970: 1_700_000_000), rewatch: true))
        let post = try #require(t.expressions.last)
        #expect(post.contains("/s/save-diary-entry"))
        #expect(post.contains("film:1620206"))
        #expect(post.contains("TOKEN"))
        #expect(post.contains("rewatch"))
        #expect(post.contains("specifiedDate"))
    }

    /// A film Letterboxd does not know cannot be written, and retrying will not help.
    @Test func anUnknownFilmIsFilmNotFound() async {
        let t = ScriptedTransport(pageValue: goodPage(), postValue: goodPost())
        await #expect(throws: LetterboxdError.filmNotFound) {
            try await writer(t, slugs: [:]).write(LetterboxdWrite(tmdbID: 99, rating: nil))
        }
    }

    /// No token means the page did not load as a signed-in member.
    @Test func aPageWithoutACsrfIsNotAuthenticated() async {
        let t = ScriptedTransport(pageValue: ["uid": "film:1"], postValue: goodPost())
        await #expect(throws: LetterboxdError.notAuthenticated) {
            try await writer(t).write(LetterboxdWrite(tmdbID: 550, rating: nil))
        }
    }

    @Test func aChallengedPostIsChallenged() async {
        let t = ScriptedTransport(pageValue: goodPage(),
                                  postValue: ["status": 403, "ok": false,
                                              "body": "Just a moment..."] as [String: any Sendable])
        await #expect(throws: LetterboxdError.challenged) {
            try await writer(t).write(LetterboxdWrite(tmdbID: 550, rating: nil))
        }
    }

    /// A plain 403 is a dead session, not a challenge — they need different fixes, and sending the
    /// owner to the wrong one wastes their time.
    @Test func aPlain403IsNotAuthenticated() async {
        let t = ScriptedTransport(pageValue: goodPage(),
                                  postValue: ["status": 403, "ok": false, "body": "nope"] as [String: any Sendable])
        await #expect(throws: LetterboxdError.notAuthenticated) {
            try await writer(t).write(LetterboxdWrite(tmdbID: 550, rating: nil))
        }
    }

    @Test func aServerErrorIsTransient() async {
        let t = ScriptedTransport(pageValue: goodPage(),
                                  postValue: ["status": 502, "ok": false, "body": ""] as [String: any Sendable])
        await #expect(throws: LetterboxdError.transient("save-diary-entry returned 502")) {
            try await writer(t).write(LetterboxdWrite(tmdbID: 550, rating: nil))
        }
    }
}
