import Foundation

/// Starts a Real-Debrid download for a torrent (by infohash) and returns its initial info.
/// Unlike the instant-only add, this keeps the torrent so RD downloads it in the background.
public protocol DownloadRequesting: Sendable {
    func startDownload(infoHash: String) async throws -> TorrentInfo
}

public struct RealDebridDownloadService: DownloadRequesting {
    private let torrents: TorrentsClient
    public init(torrents: TorrentsClient) { self.torrents = torrents }
    public func startDownload(infoHash: String) async throws -> TorrentInfo {
        try await torrents.addForDownload(magnetHash: infoHash)
    }
}
