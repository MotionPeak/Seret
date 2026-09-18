import Foundation

public enum ChromeError: Error, Equatable {
    case noPageTarget
    case evaluationFailed(String)
    /// The page never became the one that was asked for. Carries where the browser actually
    /// stopped, because the usual cause is a redirect somewhere else, not a slow page.
    case navigationTimedOut(requested: String, at: String, state: String)
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

    /// Navigates, and waits until the page is actually there.
    ///
    /// `Page.navigate` returns once the navigation is committed, not once the document exists, so
    /// a navigate that does not wait hands the next read the page being replaced — which surfaces
    /// as a missing form or a signed-out session rather than as a race.
    public func navigate(to url: String,
                         timeout: Duration = .seconds(30),
                         poll: Duration = .milliseconds(250)) async throws {
        _ = try await transport.send(method: "Page.navigate", params: ["url": url])

        let deadline = ContinuousClock.now.advanced(by: timeout)
        var href = "", state = ""
        repeat {
            let document = try await evaluate(Self.documentState)
            href = (document["href"] as? String) ?? ""
            state = (document["ready"] as? String) ?? ""
            // `interactive` is enough: the DOM is parsed, and the form and token are server
            // rendered. Waiting for `complete` would wait on every ad and tracker on the page.
            if state == "interactive" || state == "complete", Self.isSamePage(href, url) { return }
            try await Task.sleep(for: poll)
        } while ContinuousClock.now < deadline

        throw ChromeError.navigationTimedOut(requested: url, at: href, state: state)
    }

    private static let documentState = "({ href: location.href, ready: document.readyState })"

    /// A trailing slash or a tracking query is not a different page.
    static func isSamePage(_ href: String, _ url: String) -> Bool {
        func path(_ value: String) -> String {
            var trimmed = value
            if let cut = trimmed.firstIndex(where: { $0 == "?" || $0 == "#" }) {
                trimmed = String(trimmed[trimmed.startIndex..<cut])
            }
            while trimmed.hasSuffix("/") { trimmed.removeLast() }
            return trimmed
        }
        return path(href) == path(url)
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
