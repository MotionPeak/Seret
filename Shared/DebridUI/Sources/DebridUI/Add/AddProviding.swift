import DebridCore

/// Adds a torrent (by infohash) to the user's RD account.
public protocol AddProviding: Sendable {
    /// Add an already-cached torrent — instant; rejects/cleans up a non-instant pick.
    func add(infoHash: String) async throws -> TorrentInfo
    /// Add a torrent for background download (uncached allowed) — keeps the torrent and returns
    /// while it's still downloading. Backs the "request download" path for brand-new titles.
    func addForDownload(infoHash: String) async throws -> TorrentInfo
}

public struct RealDebridAddService: AddProviding {
    let torrents: TorrentsClient
    public init(torrents: TorrentsClient) { self.torrents = torrents }
    public func add(infoHash: String) async throws -> TorrentInfo {
        try await torrents.add(magnetHash: infoHash)
    }
    public func addForDownload(infoHash: String) async throws -> TorrentInfo {
        try await torrents.addForDownload(magnetHash: infoHash)
    }
}
