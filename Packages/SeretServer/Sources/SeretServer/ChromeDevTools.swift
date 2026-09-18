import Foundation

public enum ChromeError: Error, Equatable {
    case noPageTarget
    case evaluationFailed(String)
}

/// One DevTools-protocol round trip.
///
/// A seam, so `ChromeSession` is testable without spinning up Chromium — and because the real
/// transport needs a WebSocket, which has no place in a unit test.
public protocol CDPTransport: Sendable {
    func send(method: String, params: [String: any Sendable]) async throws -> [String: any Sendable]
}

/// Drives the signed-in Chromium on the NAS.
///
/// This exists because Cloudflare refuses every non-browser client — measured with a full valid
/// session, a cf_clearance token and Chrome's exact User-Agent, all of which still got 403. The
/// only thing that can write to Letterboxd is a browser, so Seret drives one.
public actor ChromeSession {
    private let transport: any CDPTransport

    public init(transport: any CDPTransport) { self.transport = transport }

    public func navigate(to url: String) async throws {
        _ = try await transport.send(method: "Page.navigate", params: ["url": url])
    }

    /// Evaluates JS and returns its value, which must be JSON-serialisable.
    public func evaluate(_ expression: String) async throws -> [String: any Sendable] {
        let reply = try await transport.send(
            method: "Runtime.evaluate",
            params: ["expression": expression, "returnByValue": true, "awaitPromise": true])

        // An exception must not read as an empty result: that would look like a write that
        // succeeded and did nothing.
        if let details = reply["exceptionDetails"] as? [String: any Sendable] {
            throw ChromeError.evaluationFailed((details["text"] as? String) ?? "unknown")
        }
        let result = reply["result"] as? [String: any Sendable]
        return (result?["value"] as? [String: any Sendable]) ?? [:]
    }
}
