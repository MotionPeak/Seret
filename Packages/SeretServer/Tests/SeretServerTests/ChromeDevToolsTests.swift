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

@Suite struct ChromeDevToolsTests {
    @Test func navigateSendsPageNavigate() async throws {
        let transport = FakeTransport()
        try await ChromeSession(transport: transport).navigate(to: "https://letterboxd.com/film/speed/")
        #expect(transport.methods == ["Page.navigate"])
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
