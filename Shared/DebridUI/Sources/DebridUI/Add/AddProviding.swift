import DebridCore

/// Adds an already-cached torrent (by infohash) to the user's RD account.
public protocol AddProviding: Sendable {
    func add(infoHash: String) async throws -> TorrentInfo
}

public struct RealDebridAddService: AddProviding {
    let torrents: TorrentsClient
    public init(torrents: TorrentsClient) { self.torrents = torrents }
    public func add(infoHash: String) async throws -> TorrentInfo {
        try await torrents.add(magnetHash: infoHash)
    }
}
