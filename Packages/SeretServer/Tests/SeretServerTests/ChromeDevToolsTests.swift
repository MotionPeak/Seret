import Testing
import Foundation
@testable import SeretServer

final class FakeTransport: CDPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [String] = []
    private let replies: [String: [String: any Sendable]]

    init(replies: [String: [String: any Sendable]] = [:]) {
        self.replies = replies
    }

    // `withLock`, not lock()/unlock(): the bare calls are unavailable from an async context.
    var methods: [String] { lock.withLock { calls } }

    func send(method: String, params: [String: any Sendable]) async throws -> [String: any Sendable] {
        lock.withLock { calls.append(method) }
        return replies[method] ?? [:]
    }
}

/// A transport whose `Runtime.evaluate` answers change from call to call, so a page can be caught
/// mid-load the way a real one is.
private final class PageStateTransport: CDPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [String] = []
    private var documents: [(href: String, ready: String)]
    private let last: (href: String, ready: String)

    /// The last document state repeats once the script runs out.
    init(documents: [(href: String, ready: String)]) {
        self.documents = documents
        self.last = documents.last ?? (href: "", ready: "loading")
    }

    var methods: [String] { lock.withLock { calls } }

    func send(method: String, params: [String: any Sendable]) async throws -> [String: any Sendable] {
        lock.withLock { calls.append(method) }
        guard method == "Runtime.evaluate" else { return [:] }
        let document = lock.withLock { documents.isEmpty ? last : documents.removeFirst() }
        return ["result": ["value": ["href": document.href, "ready": document.ready]
                                as [String: any Sendable]] as [String: any Sendable]]
    }
}

@Suite struct ChromeDevToolsTests {
    /// `Page.navigate` returns when the navigation is committed, not when the page exists, so a
    /// navigate that does not wait hands the next read the document being replaced.
    @Test func navigateWaitsForTheDocument() async throws {
        let film = "https://letterboxd.com/film/speed/"
        let transport = PageStateTransport(documents: [
            (href: "https://letterboxd.com/", ready: "loading"),
            (href: film, ready: "loading"),
            (href: film, ready: "complete")
        ])
        try await ChromeSession(transport: transport).navigate(to: film, timeout: .seconds(1), poll: .milliseconds(1))
        #expect(transport.methods == ["Page.navigate", "Runtime.evaluate",
                                      "Runtime.evaluate", "Runtime.evaluate"])
    }

    /// A Letterboxd film page loads dozens of ad and tracker scripts after its own markup, so
    /// waiting for `complete` would wait on all of them for a form that is already there.
    @Test func aParsedDocumentIsEnough() async throws {
        let film = "https://letterboxd.com/film/speed/"
        let transport = PageStateTransport(documents: [(href: film, ready: "interactive")])
        try await ChromeSession(transport: transport).navigate(to: film, timeout: .seconds(1), poll: .milliseconds(1))
        #expect(transport.methods == ["Page.navigate", "Runtime.evaluate"])
    }

    @Test func navigateGivesUpSayingWhereItStopped() async throws {
        let transport = PageStateTransport(documents: [
            (href: "https://letterboxd.com/sign-in/", ready: "complete")
        ])
        await #expect(throws: ChromeError.navigationTimedOut(
            requested: "https://letterboxd.com/film/speed/",
            at: "https://letterboxd.com/sign-in/",
            state: "complete")) {
            try await ChromeSession(transport: transport)
                .navigate(to: "https://letterboxd.com/film/speed/",
                          timeout: .milliseconds(5), poll: .milliseconds(1))
        }
    }

    @Test func aTrailingSlashOrAQueryIsTheSamePage() {
        let film = "https://letterboxd.com/film/speed/"
        #expect(ChromeSession.isSamePage("https://letterboxd.com/film/speed", film))
        #expect(ChromeSession.isSamePage(film + "?utm_source=x", film))
        #expect(!ChromeSession.isSamePage("https://letterboxd.com/film/speed-2/", film))
        #expect(!ChromeSession.isSamePage("about:blank", film))
    }

    @Test func evaluateReturnsTheValue() async throws {
        let transport = FakeTransport(replies: [
            "Runtime.evaluate": ["result": ["value": ["ok": true] as [String: any Sendable]]
                                     as [String: any Sendable]]
        ])
        let value = try await ChromeSession(transport: transport).evaluate("1+1")
        #expect(value["ok"] as? Bool == true)
    }

    /// A thrown JS exception is a failure, not an empty result — silently returning nothing would
    /// look exactly like a write that succeeded and did nothing.
    @Test func aJavaScriptExceptionIsAnError() async {
        let transport = FakeTransport(replies: [
            "Runtime.evaluate": ["exceptionDetails": ["text": "ReferenceError"] as [String: any Sendable]]
        ])
        await #expect(throws: ChromeError.evaluationFailed("ReferenceError")) {
            _ = try await ChromeSession(transport: transport).evaluate("boom()")
        }
    }
}
