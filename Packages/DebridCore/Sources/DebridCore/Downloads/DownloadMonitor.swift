import Foundation

/// Minimal seam over RD torrent info, so the monitor is testable without the network.
public protocol DownloadInfoProviding: Sendable {
    func info(id: String) async throws -> TorrentInfo
}

extension TorrentsClient: DownloadInfoProviding {}

/// Polls the active download requests against RD and reports their progress. When a request
/// reaches a terminal phase (`.ready` or `.failed`) its record is removed — a `.ready` title now
/// appears in the normal library; a `.failed` one is surfaced to the caller for "try another".
public actor DownloadMonitor {
    private let info: any DownloadInfoProviding
    private let store: DownloadsStore

    public init(info: any DownloadInfoProviding, store: DownloadsStore) {
        self.info = info
        self.store = store
    }

    /// One pass over all active requests. Returns this pass's statuses (terminal ones included so
    /// the caller can react/notify). A request whose info fetch fails is skipped and left tracked.
    @discardableResult
    public func poll() async throws -> [DownloadStatus] {
        let requests = try await store.all()
        var statuses: [DownloadStatus] = []
        for request in requests {
            guard let i = try? await info.info(id: request.torrentID) else { continue }
            let status = DownloadStatus(from: i, tmdbID: request.tmdbID)
            statuses.append(status)
            switch status.phase {
            case .ready, .failed:
                try? await store.delete(torrentID: request.torrentID)
            case .queued, .downloading:
                break
            }
        }
        return statuses
    }
}
