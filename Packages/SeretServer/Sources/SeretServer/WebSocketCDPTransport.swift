import Foundation
import AsyncHTTPClient
import NIOCore
import NIOPosix
import WebSocketKit

/// Guards a continuation that two callbacks race to resume. Resuming twice traps.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var taken = false

    /// True exactly once, for whichever caller gets there first.
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if taken { return false }
        taken = true
        return true
    }
}

/// Talks to the NAS Chromium's DevTools endpoint over a WebSocket.
///
/// The container name only resolves on the `letterboxd-net` docker network, which is where
/// SeretServer joins it; `LETTERBOXD_CDP` overrides the host for local testing.
///
/// Chromium binds DevTools to its own loopback and ignores `--remote-debugging-address`, so a
/// socat sidecar sharing its network namespace is what makes this port reachable at all. See
/// `Scripts/letterboxd-cdp-bridge.sh`.
public actor WebSocketCDPTransport: CDPTransport {
    public enum TransportError: Error, Equatable {
        case noPageTarget
        case notConnected
        case timedOut(String)
        case unresolvableHost(String)
    }

    private let httpBase: String
    private let group: EventLoopGroup
    private var socket: WebSocket?
    private var nextID = 0
    private var pending: [Int: CheckedContinuation<[String: any Sendable], any Error>] = [:]

    public init(httpBase: String = ProcessInfo.processInfo.environment["LETTERBOXD_CDP"]
                                    ?? "http://letterboxd-chromium:9223",
                group: EventLoopGroup = MultiThreadedEventLoopGroup.singleton) {
        self.httpBase = httpBase
        self.group = group
    }

    /// DevTools accepts a `Host` header that is an IP address or `localhost`, and refuses
    /// everything else with "Host header is specified and is not an IP address or localhost".
    static func hostNeedsResolving(_ host: String) -> Bool {
        host != "localhost" && (try? SocketAddress(ipAddress: host, port: 0)) == nil
    }

    /// `base` with its host swapped for `host`, keeping the scheme and port.
    static func base(_ base: String, host: String) -> String? {
        guard var components = URLComponents(string: base) else { return nil }
        components.host = host
        return components.string
    }

    /// The DevTools endpoint with a host DevTools will actually answer to.
    ///
    /// A docker service name is a hostname, so `letterboxd-chromium:9223` is refused outright —
    /// the name has to become an address before it ever reaches the wire. Doing it here fixes the
    /// WebSocket upgrade too, because DevTools echoes whatever Host it was given straight back in
    /// `webSocketDebuggerUrl`.
    private func resolvedBase() throws -> String {
        guard let components = URLComponents(string: httpBase), let host = components.host else {
            throw TransportError.noPageTarget
        }
        guard Self.hostNeedsResolving(host) else { return httpBase }

        // getaddrinfo blocks. It is one lookup against docker's embedded DNS per connect, inside
        // an operation that is about to drive a whole browser, so it is not worth a thread hop.
        guard let address = try? SocketAddress.makeAddressResolvingHost(host,
                                                                       port: components.port ?? 80),
              let ip = address.ipAddress,
              let resolved = Self.base(httpBase, host: ip) else {
            throw TransportError.unresolvableHost(host)
        }
        return resolved
    }

    /// The first page target on the browser, preferring one already on Letterboxd.
    func pageWebSocketURL() async throws -> String {
        // AsyncHTTPClient rather than URLSession: Chrome's DevTools writes `Content-Length:404`
        // with no space after the colon. That is legal HTTP, almost nothing else does it, and
        // swift-corelibs-foundation refuses it outright — "Failed writing header", indistinguishable
        // from the browser being down. NIO's parser reads it.
        let request = HTTPClientRequest(url: try resolvedBase() + "/json")
        let response = try await HTTPClient.shared.execute(request, timeout: .seconds(15))
        guard response.status == .ok else { throw TransportError.noPageTarget }

        let body = try await response.body.collect(upTo: 4 << 20)
        let targets = (try? JSONSerialization.jsonObject(with: Data(body.readableBytesView)))
                        as? [[String: Any]] ?? []
        let pages = targets.filter { ($0["type"] as? String) == "page" }
        let preferred = pages.first { ($0["url"] as? String)?.contains("letterboxd.com") == true }
        guard let target = preferred ?? pages.first,
              let ws = target["webSocketDebuggerUrl"] as? String else {
            throw TransportError.noPageTarget
        }
        return ws
    }

    private func connectIfNeeded() async throws {
        if socket?.isClosed == false { return }

        let wsURL = try await pageWebSocketURL()
        // The success callback and the failure future can both fire; resuming a continuation twice
        // is a crash, so the flag is shared state and needs a lock rather than a captured `var`.
        let once = ResumeOnce()
        let connected: WebSocket = try await withCheckedThrowingContinuation { continuation in
            WebSocket.connect(to: wsURL, on: group) { ws in
                // Installed here, inside the upgrade, because WebSocketKit keeps the handler in a
                // NIOLoopBoundBox: setting it anywhere but the socket's own event loop traps the
                // process outright. This closure already runs there, and it runs before any frame
                // can arrive, so nothing is missed either.
                ws.onText { [weak self] _, text in
                    Task { await self?.deliver(text) }
                }
                if once.claim() { continuation.resume(returning: ws) }
            }.whenFailure { error in
                if once.claim() { continuation.resume(throwing: error) }
            }
        }

        socket = connected
    }

    /// Replies arrive out of order, so they are matched by the `id` that was sent with the request.
    private func deliver(_ text: String) {
        guard let data = text.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let id = object["id"] as? Int,
              let continuation = pending.removeValue(forKey: id) else { return }

        if let error = object["error"] as? [String: Any] {
            let message = (error["message"] as? String) ?? "CDP error"
            continuation.resume(throwing: ChromeError.evaluationFailed(message))
        } else {
            continuation.resume(returning: (object["result"] as? [String: any Sendable]) ?? [:])
        }
    }

    public func send(method: String, params: [String: any Sendable]) async throws -> [String: any Sendable] {
        try await connectIfNeeded()
        guard let socket, !socket.isClosed else { throw TransportError.notConnected }

        nextID += 1
        let id = nextID
        let payload: [String: Any] = ["id": id, "method": method, "params": params]
        let data = try JSONSerialization.data(withJSONObject: payload)

        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            socket.send(String(decoding: data, as: UTF8.self))
        }
    }

    public func close() async {
        try? await socket?.close()
        socket = nil
    }
}
