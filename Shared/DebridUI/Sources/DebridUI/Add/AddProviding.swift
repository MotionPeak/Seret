import DebridCore

/// Adds an already-cached torrent (by infohash) to the user's debrid account.
public protocol AddProviding: Sendable {
    func add(infoHash: String) async throws -> TorrentInfo
}

/// Adds through any debrid client. Handed the composite, which sends the add to the add target.
public struct DebridAddService: AddProviding {
    let client: any DebridClient
    public init(client: any DebridClient) { self.client = client }
    public func add(infoHash: String) async throws -> TorrentInfo {
        try await client.add(magnetHash: infoHash)
    }
}
