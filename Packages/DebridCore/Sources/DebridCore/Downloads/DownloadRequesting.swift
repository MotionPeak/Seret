import Foundation

/// Starts a background download for a torrent (by infohash) and returns its initial info.
/// Unlike the instant-only add, this keeps the torrent so the provider downloads it.
public protocol DownloadRequesting: Sendable {
    func startDownload(infoHash: String) async throws -> TorrentInfo
}

/// Starts downloads on a debrid client — for the composite, on its add target.
public struct DebridDownloadService: DownloadRequesting {
    private let client: any DebridClient
    public init(client: any DebridClient) { self.client = client }
    public func startDownload(infoHash: String) async throws -> TorrentInfo {
        try await client.addForDownload(magnetHash: infoHash)
    }
}
