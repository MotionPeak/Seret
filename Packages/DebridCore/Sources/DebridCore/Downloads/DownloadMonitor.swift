#if canImport(SwiftData)
import Foundation

/// Minimal seam over RD torrent info, so the monitor is testable without the network.
public protocol DownloadInfoProviding: Sendable {
    func info(id: String) async throws -> TorrentInfo
}

extension TorrentsClient: DownloadInfoProviding {}

/// Polls the active download requests against RD and reports their progress. When a request
/// reaches a terminal phase (`.ready` or `.failed`) its record is removed — a `.ready` title now
/// appears in the normal library; a `.failed` one is surfaced to the caller for "try another".
///
/// Holds one `ETAEstimator` per torrent so the reported remaining time is smoothed across polls
/// rather than recomputed from RD's jumpy instantaneous speed.
public actor DownloadMonitor {
    private let info: any DownloadInfoProviding
    private let store: DownloadsStore
    private let now: @Sendable () -> Date
    private var estimators: [String: ETAEstimator] = [:]

    public init(info: any DownloadInfoProviding, store: DownloadsStore,
                now: @escaping @Sendable () -> Date = Date.init) {
        self.info = info
        self.store = store
        self.now = now
    }

    /// One pass over all active requests. Returns this pass's statuses (terminal ones included so
    /// the caller can react/notify). A request whose info fetch fails is skipped and left tracked.
    @discardableResult
    public func poll() async throws -> [DownloadStatus] {
        let requests = try await store.all()
        var statuses: [DownloadStatus] = []
        for request in requests {
            guard let i = try? await info.info(id: request.torrentID) else { continue }
            var estimator = estimators[request.torrentID] ?? ETAEstimator()
            let eta = estimator.observe(fraction: i.progress / 100, totalBytes: i.bytes,
                                        reportedSpeed: i.speed, at: now())
            estimators[request.torrentID] = estimator
            let status = DownloadStatus(from: i, contentKey: request.contentKey,
                                        tmdbID: request.tmdbID, secondsRemaining: eta)
            statuses.append(status)
            switch status.phase {
            case .ready, .failed:
                estimators[request.torrentID] = nil   // otherwise this grows forever
                try? await store.delete(torrentID: request.torrentID)
            case .queued, .downloading:
                break
            }
        }
        return statuses
    }
}
#endif
