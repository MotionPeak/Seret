import Foundation
import DebridCore
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
    }

    private let httpBase: String
    private let group: EventLoopGroup
    private let http = HTTPClient()
    private var socket: WebSocket?
    private var nextID = 0
    private var pending: [Int: CheckedContinuation<[String: any Sendable], any Error>] = [:]

    public init(httpBase: String = ProcessInfo.processInfo.environment["LETTERBOXD_CDP"]
                                    ?? "http://letterboxd-chromium:9223",
                group: EventLoopGroup = MultiThreadedEventLoopGroup.singleton) {
        self.httpBase = httpBase
        self.group = group
    }

    /// The first page target on the browser, preferring one already on Letterboxd.
    private func pageWebSocketURL() async throws -> String {
        guard let url = URL(string: httpBase + "/json") else { throw TransportError.noPageTarget }
        // DebridCore's client rather than URLSession directly: on Linux URLSession lives in
        // FoundationNetworking, and that client already carries the guard.
        let data = try await http.data(url)
        let targets = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] ?? []
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
                if once.claim() { continuation.resume(returning: ws) }
            }.whenFailure { error in
                if once.claim() { continuation.resume(throwing: error) }
            }
        }

        connected.onText { [weak self] _, text in
            Task { await self?.deliver(text) }
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
