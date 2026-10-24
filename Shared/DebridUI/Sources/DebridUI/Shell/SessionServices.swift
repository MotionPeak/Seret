import DebridCore

/// Thrown by a vended service whose session has no signed-in stack any more.
public enum SessionServiceError: Error, Equatable, Sendable { case signedOut }

/// The session's add service, resolved on EVERY call rather than captured when the screen opened.
///
/// An Add page can outlive an add-target change: tvOS keeps one alive in Find's navigation stack
/// while Settings switches the target, and `signOut(of:)` can remove its account entirely. A
/// captured service would keep adding to the old target, or to an account no longer signed in.
struct SessionAddService: AddProviding {
    let current: @Sendable () async -> AddProviding?

    func add(infoHash: String) async throws -> TorrentInfo {
        guard let service = await current() else { throw SessionServiceError.signedOut }
        return try await service.add(infoHash: infoHash)
    }
}

/// The session's stream source, resolved on every call — so search asks the cache of the account
/// the add will actually land on. See `SessionAddService`.
struct SessionStreamSource: StreamSource {
    let current: @Sendable () async -> StreamSource?

    func streams(for query: StreamQuery) async throws -> [CachedStream] {
        guard let source = await current() else { throw SessionServiceError.signedOut }
        return try await source.streams(for: query)
    }

    func streams(for query: StreamQuery, includeUncached: Bool) async throws -> [CachedStream] {
        guard let source = await current() else { throw SessionServiceError.signedOut }
        return try await source.streams(for: query, includeUncached: includeUncached)
    }
}
