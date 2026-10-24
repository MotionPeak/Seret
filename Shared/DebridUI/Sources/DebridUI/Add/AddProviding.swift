import DebridCore

/// Adds an already-cached torrent (by infohash) to the user's debrid account.
public protocol AddProviding: Sendable {
    func add(infoHash: String) async throws -> TorrentInfo
    /// The account an add lands on, for copy that names it. nil when unknown.
    func target() async -> DebridProvider?
}

extension AddProviding {
    public func target() async -> DebridProvider? { nil }
}

/// Adds through any debrid client. Handed the composite, which sends the add to the add target.
public struct DebridAddService: AddProviding {
    let client: any DebridClient
    public init(client: any DebridClient) { self.client = client }
    public func add(infoHash: String) async throws -> TorrentInfo {
        try await client.add(magnetHash: infoHash)
    }
    /// The composite's `provider` IS the add target.
    public func target() async -> DebridProvider? { client.provider }
}
