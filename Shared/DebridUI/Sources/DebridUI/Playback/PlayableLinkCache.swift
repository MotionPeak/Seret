import Foundation

/// In-memory, short-TTL cache of unrestricted (playable) URLs, keyed by the RD restricted link.
/// Lets the Detail screen resolve the RD `unrestrict` call *before* Play is tapped, so the player
/// starts with zero network round-trips ahead of VLC's connect.
///
/// Honors "unrestricted links expire — resolve at play time, never store": nothing persists,
/// entries live at most `ttl`, and `consume` is ONE-SHOT (an entry is removed as it is vended),
/// so a retry after a playback failure always re-resolves fresh from Real-Debrid.
public actor PlayableLinkCache {
    public typealias Resolver = @Sendable (String) async throws -> URL

    private struct Flight { let id: UUID; let task: Task<URL, Error> }

    private let resolve: Resolver
    private let ttl: TimeInterval
    private let now: @Sendable () -> Date
    private var ready: [String: (url: URL, resolvedAt: Date)] = [:]
    private var inFlight: [String: Flight] = [:]

    public init(ttl: TimeInterval = 8 * 60,
                now: @escaping @Sendable () -> Date = Date.init,
                resolve: @escaping Resolver) {
        self.ttl = ttl
        self.now = now
        self.resolve = resolve
    }

    /// Start resolving `link` in the background. No-op when a fresh entry or an in-flight
    /// resolve already exists. A failed prefetch is dropped silently — the next `consume`
    /// resolves fresh and surfaces any real error there.
    public func prefetch(_ link: String) {
        guard inFlight[link] == nil, freshURL(link) == nil else { return }
        let id = UUID()
        let task = Task { [resolve] in try await resolve(link) }
        inFlight[link] = Flight(id: id, task: task)
        Task { [weak self] in
            let url = try? await task.value
            await self?.finishPrefetch(link, id: id, url: url)
        }
    }

    /// The playable URL for `link`: a fresh prefetched entry (consumed — one-shot), an
    /// in-flight prefetch (awaited and consumed, its error surfacing here), or a direct resolve.
    public func consume(_ link: String) async throws -> URL {
        if let hit = freshURL(link) {
            ready[link] = nil
            return hit
        }
        if let flight = inFlight[link] {
            inFlight[link] = nil
            return try await flight.task.value
        }
        return try await resolve(link)
    }

    /// Record a settled prefetch — only if this flight is still the registered one (a consume
    /// or a newer prefetch may have claimed the slot mid-flight).
    private func finishPrefetch(_ link: String, id: UUID, url: URL?) {
        guard inFlight[link]?.id == id else { return }
        inFlight[link] = nil
        if let url { ready[link] = (url, now()) }
    }

    private func freshURL(_ link: String) -> URL? {
        guard let entry = ready[link] else { return nil }
        guard now().timeIntervalSince(entry.resolvedAt) < ttl else {
            ready[link] = nil
            return nil
        }
        return entry.url
    }
}
