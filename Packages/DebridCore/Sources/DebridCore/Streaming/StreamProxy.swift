import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The seam the player uses: put the stream cache in front of an RD link, or not.
public protocol StreamProxying: Sendable {
    /// A URL libvlc can open for `upstream` — or `upstream` itself when the cache is unavailable.
    /// `refreshUpstream` re-unrestricts the file when RD says the link expired.
    func open(upstream: URL, fileKey: String,
              refreshUpstream: @escaping @Sendable () async throws -> URL) async -> StreamHandle
    /// The first frame is on screen: what was read so far is kept for the next open.
    func markPlaybackStarted(_ handle: StreamHandle) async
    /// Stop fetching, keep the resume region, free the RAM.
    func close(_ handle: StreamHandle) async
    /// Memory warning: drop history, keep read-ahead.
    func trimMemory() async
    /// Why RD is not serving the stream, if it is not — it refused, or it is failing right now
    /// (the network is down): the player asks when libvlc reports the end, because either reaches
    /// libvlc as a plain EOF, and only a refusal is final.
    func upstreamFailure(_ handle: StreamHandle) async -> UpstreamFailure?
}

/// What the player plays: the loopback URL of a session, or RD's link directly.
public struct StreamHandle: Sendable, Hashable {
    public let url: URL
    let sessionID: UUID?

    /// A handle that is just `url`, with no session behind it (the fallback, and test fakes).
    public init(direct url: URL) {
        self.url = url
        sessionID = nil
    }

    init(url: URL, sessionID: UUID) {
        self.url = url
        self.sessionID = sessionID
    }
}

/// The stream cache: one loopback server for the app, one session per open file.
public actor StreamProxy: StreamProxying {
    private let budget: StreamCacheBudget
    private let index: IndexStore
    private let makeConfiguration: @Sendable () -> URLSessionConfiguration
    private let log: @Sendable (String) -> Void
    private var sessions: [UUID: StreamSession] = [:]
    #if canImport(Network)
    private var server: LoopbackStreamServer?
    private var port: UInt16?
    /// A start in progress. Starting suspends this actor; a second open arriving meanwhile must
    /// wait for it, not start a second server that would release the first and kill its port.
    private var starting: Task<UInt16?, Never>?
    #endif

    /// RD traffic without URLCache: 206s of a 60 GB file are not worth caching twice.
    ///
    /// Offline, a fetch fails at once (-1009) rather than `waitsForConnectivity`: a fetch quietly
    /// waiting for the network would hide the outage from the session, which paces its retries
    /// and must tell the player why the stream stopped (`StreamSession.clearToFetch`).
    public static let defaultConfiguration: @Sendable () -> URLSessionConfiguration = {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        return configuration
    }

    public init(budget: StreamCacheBudget, indexDirectory: URL,
                makeConfiguration: @escaping @Sendable () -> URLSessionConfiguration = StreamProxy.defaultConfiguration,
                log: @escaping @Sendable (String) -> Void = { _ in }) {
        self.budget = budget
        self.index = IndexStore(directory: indexDirectory, chunkSize: budget.chunkSize,
                                perFileLimit: budget.indexBytesPerFile,
                                totalLimit: budget.indexBytesTotal)
        self.makeConfiguration = makeConfiguration
        self.log = log
    }

    public func open(upstream: URL, fileKey: String,
                     refreshUpstream: @escaping @Sendable () async throws -> URL) async -> StreamHandle {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-noStreamProxy") {
            return StreamHandle(direct: upstream)
        }
        #endif
        #if canImport(Network)
        guard let port = await ensureServer() else { return StreamHandle(direct: upstream) }
        let id = UUID()
        sessions[id] = StreamSession(id: id, fileKey: fileKey, upstream: upstream,
                                     refreshUpstream: refreshUpstream, budget: budget, index: index,
                                     makeConfiguration: makeConfiguration, log: log)
        log("session \(id.uuidString.prefix(8)) opened for \(fileKey)")
        // Ends in the film's file name: the player's log names the film again (not a UUID), and
        // libvlc gets the same extension hint it had from the RD link.
        let url = URL(string: "http://127.0.0.1:\(port)/s/\(id.uuidString)")!
            .appendingPathComponent(upstream.lastPathComponent)
        return StreamHandle(url: url, sessionID: id)
        #else
        return StreamHandle(direct: upstream)
        #endif
    }

    public func markPlaybackStarted(_ handle: StreamHandle) async {
        guard let id = handle.sessionID else { return }
        await sessions[id]?.markPlaybackStarted()
    }

    public func close(_ handle: StreamHandle) async {
        guard let id = handle.sessionID, let session = sessions.removeValue(forKey: id) else { return }
        await session.close()
        #if canImport(Network)
        server?.closeConnections(for: id)                        // a send libvlc stopped reading
        #endif
        log("session \(id.uuidString.prefix(8)) closed")
    }

    public func upstreamFailure(_ handle: StreamHandle) async -> UpstreamFailure? {
        guard let id = handle.sessionID else { return nil }
        return await sessions[id]?.upstreamState
    }

    public func trimMemory() async {
        for session in sessions.values { await session.trimMemory() }
    }

    func session(_ id: UUID) -> StreamSession? { sessions[id] }

    #if canImport(Network)
    /// The server, started on first use and restored if it stopped answering. nil when it cannot
    /// start — the caller then plays RD's link directly, exactly as before this cache existed.
    ///
    /// "Answering" is a real connection, every time: after the app sat suspended the system had
    /// taken the socket back while the listener still read `ready`, and an open trusting that
    /// handed libvlc a dead port — "Playback failed." until the app was relaunched, Retry included.
    private func ensureServer() async -> UInt16? {
        if let starting { return await starting.value }
        if let port, server?.isAccepting() == true { return port }
        let start = Task { await restoreServer() }
        starting = start
        let port = await start.value
        starting = nil
        return port
    }

    /// Run on the way back to the foreground. A film paused across the suspension keeps the URL it
    /// was given, and its next reconnect has to find the server there — not wait for an open.
    public func revive() async {
        guard server != nil else { return }                      // nothing played yet: nothing to keep
        _ = await ensureServer()
    }

    /// See `LoopbackStreamServer.dropListenerSilently`. For tests.
    func dropListenerSilently() { server?.dropListenerSilently() }

    /// Back on the port already handed out when there is one — a paused player's reconnect is
    /// addressed to it — else on a fresh one.
    private func restoreServer() async -> UInt16? {
        if let server, let port {
            log("127.0.0.1:\(port) refuses connections; listening on it again")
            do {
                try await server.listenAgain()
                if server.isAccepting() { return port }
            } catch {
                log("could not listen on \(port) again: \(error)")
            }
        }
        return await startServer()
    }

    private func startServer() async -> UInt16? {
        server?.stop()
        let server = LoopbackStreamServer(session: { [weak self] id in await self?.session(id) }, log: log)
        do {
            let port = try await server.start()
            self.server = server
            self.port = port
            log("listening on 127.0.0.1:\(port)")
            return port
        } catch {
            log("could not start: \(error)")
            return nil
        }
    }
    #endif
}
