#if canImport(Network)
import Foundation
import Network

/// A minimal HTTP/1.1 server on 127.0.0.1 that libvlc reads a stream session through.
///
/// GET and HEAD with Range, one request per connection, always `Connection: close`: libvlc opens a
/// new connection for every reposition anyway, and on loopback that costs nothing — which is the
/// whole trick, since against Real-Debrid each one cost ~460ms. Bound to 127.0.0.1 only, and a
/// session is addressed by a random UUID, so another process on the device cannot guess a stream.
final class LoopbackStreamServer: @unchecked Sendable {
    private let session: @Sendable (UUID) async -> StreamSession?
    private let log: @Sendable (String) -> Void
    private let queue = DispatchQueue(label: "seret.stream-proxy")
    private let lock = NSLock()
    private var listener: NWListener?

    /// The most a request head may be. libvlc's are ~200 bytes.
    private static let maxHeadBytes = 16 << 10
    /// How much one send carries.
    private static let sendBytes = 256 << 10

    init(session: @escaping @Sendable (UUID) async -> StreamSession?,
         log: @escaping @Sendable (String) -> Void) {
        self.session = session
        self.log = log
    }

    deinit { listener?.cancel() }

    var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return listener?.state == .ready
    }

    /// Listen on 127.0.0.1 at a free port, and return it.
    func start() async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        lock.withLock { self.listener = listener }
        return try await withCheckedThrowingContinuation { continuation in
            let once = Once()                    // the listener reports states after `ready` too
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if once.fire() { continuation.resume(returning: listener.port?.rawValue ?? 0) }
                case .failed(let error):
                    if once.fire() { continuation.resume(throwing: error) }
                case .cancelled:
                    if once.fire() { continuation.resume(throwing: CancellationError()) }
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        lock.lock(); let listener = self.listener; self.listener = nil; lock.unlock()
        listener?.cancel()
    }

    /// True the first time only — a continuation must be resumed exactly once.
    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var fired = false
        func fire() -> Bool {
            lock.lock(); defer { lock.unlock() }
            if fired { return false }
            fired = true
            return true
        }
    }

    // MARK: - Connections

    private func accept(_ connection: NWConnection) {
        let task = Task { await self.serve(connection) }
        // libvlc hangs up on every reposition: stop the read it was waiting on.
        connection.stateUpdateHandler = { state in
            switch state {
            case .failed, .cancelled: task.cancel()
            default: break
            }
        }
        connection.start(queue: queue)
    }

    private func serve(_ connection: NWConnection) async {
        defer { connection.cancel() }
        guard let raw = try? await Self.receiveHead(connection),
              let head = HTTPRequestHead(raw) else { return }
        guard head.method == "GET" || head.method == "HEAD",
              let id = head.sessionID, let session = await session(id) else {
            try? await Self.send(HTTPResponseHead.error(404), on: connection)
            return
        }
        var headSent = false
        do {
            let (total, type) = try await session.head()
            guard let range = RangeRequest.parse(head.range).resolve(total: total) else {
                try await Self.send(HTTPResponseHead.error(416), on: connection)
                return
            }
            let response = head.range == nil
                ? HTTPResponseHead.whole(total: total, contentType: type)
                : HTTPResponseHead.partial(range, total: total, contentType: type)
            try await Self.send(response, on: connection)
            headSent = true
            guard head.method == "GET" else { return }
            var offset = range.lowerBound
            while offset <= range.upperBound {
                let want = Int(min(Int64(Self.sendBytes), range.upperBound - offset + 1))
                let data = try await session.read(offset: offset, max: want)
                try await Self.send(data, on: connection)
                offset += Int64(data.count)
            }
        } catch StreamError.upstreamStatus(let status) where !headSent {
            try? await Self.send(HTTPResponseHead.error(status), on: connection)
        } catch where !headSent {
            try? await Self.send(HTTPResponseHead.error(502), on: connection)
        } catch {
            // Mid-body: closing the connection is the only signal HTTP has; libvlc's
            // :http-reconnect asks again.
        }
    }

    // MARK: - NWConnection, async

    private static func receiveHead(_ connection: NWConnection) async throws -> Data {
        var buffer = Data()
        while buffer.count < maxHeadBytes {
            guard let chunk = try await receive(connection), !chunk.isEmpty else { break }
            buffer.append(chunk)
            if buffer.range(of: Data("\r\n\r\n".utf8)) != nil { return buffer }
        }
        throw StreamError.closed
    }

    private static func receive(_ connection: NWConnection) async throws -> Data? {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: maxHeadBytes) {
                data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if isComplete, data == nil {
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: data)
                }
            }
        }
    }

    private static func send(_ data: Data, on connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }
    }
}
#endif
