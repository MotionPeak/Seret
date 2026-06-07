import DebridCore
import Foundation
import Observation

/// Persistence seam for in-progress download requests (DebridCore's `DownloadsStore` conforms).
public protocol DownloadRecording: Sendable {
    func upsert(_ data: DownloadRequestData) async throws
    func all() async throws -> [DownloadRequestData]
}

/// Polling seam over RD download progress (DebridCore's `DownloadMonitor` conforms).
public protocol DownloadPolling: Sendable {
    func poll() async throws -> [DownloadStatus]
}

extension DownloadsStore: DownloadRecording {}
extension DownloadMonitor: DownloadPolling {}

/// App-wide view-model for the "request download" feature: starts uncached downloads on the RD
/// seam, persists a record, and surfaces live per-title progress (keyed by TMDB id) that drives
/// the detail-screen status row and the library "downloading" badge. A `.ready` poll flips the
/// title into the normal library (via `onReady`) and clears its badge.
@MainActor
@Observable
public final class DownloadStore {
    /// Active download status per TMDB id. Absent = nothing in flight (or already in the library).
    public private(set) var statuses: [Int: DownloadStatus] = [:]

    /// Title + poster per in-flight TMDB id — renders the library "downloading" tile and names the
    /// "ready" notification. Kept alongside `statuses` so the brain `DownloadStatus` stays minimal.
    private var meta: [Int: (title: String, posterPath: String?)] = [:]

    private let service: DownloadRequesting
    private let records: DownloadRecording
    private let poller: DownloadPolling
    private let onReady: (Int) async -> Void
    private let now: () -> Date
    private let maxAttempts: Int
    private let pollInterval: Duration
    private var pollTask: Task<Void, Never>?

    public init(service: DownloadRequesting,
                records: DownloadRecording,
                poller: DownloadPolling,
                onReady: @escaping (Int) async -> Void = { _ in },
                pollInterval: Duration = .seconds(5),
                now: @escaping () -> Date = Date.init,
                maxAttempts: Int = 6) {
        self.service = service; self.records = records; self.poller = poller
        self.onReady = onReady; self.pollInterval = pollInterval; self.now = now; self.maxAttempts = maxAttempts
    }

    public func status(forTMDB id: Int) -> DownloadStatus? { statuses[id] }

    /// The title of an in-flight download (for the "ready" notification).
    public func title(forTMDB id: Int) -> String? { meta[id]?.title }

    /// In-progress downloads (queued/downloading) as poster tiles for the library grid. Failed and
    /// ready ones are excluded — failed surfaces on Detail, ready becomes a real library item.
    public var activeTiles: [DownloadTile] {
        statuses.compactMap { tmdbID, status in
            switch status.phase {
            case .queued, .downloading:
                let m = meta[tmdbID]
                return DownloadTile(tmdbID: tmdbID, title: m?.title ?? "Downloading…",
                                    posterPath: m?.posterPath, status: status)
            case .ready, .failed:
                return nil
            }
        }
        .sorted { $0.tmdbID < $1.tmdbID }
    }

    /// Seed badges from persisted records (call at sign-in) so an in-flight download survives an
    /// app restart, then resume polling.
    public func loadActive() async {
        let active = (try? await records.all()) ?? []
        for r in active where statuses[r.tmdbID] == nil {
            statuses[r.tmdbID] = DownloadStatus(torrentID: r.torrentID, tmdbID: r.tmdbID, phase: .queued, fraction: 0)
            meta[r.tmdbID] = (r.title, r.posterPath)
        }
        if !active.isEmpty { startPolling() }
    }

    /// Start a background download for `tmdbID`, trying the ranked candidates in order until one
    /// starts (each terminal failure self-skips, mirroring the instant add's fallback).
    public func request(tmdbID: Int, title: String, kind: MediaKind, candidates: [CachedStream],
                        posterPath: String? = nil) async {
        meta[tmdbID] = (title, posterPath)
        guard !candidates.isEmpty else {
            statuses[tmdbID] = .failed(tmdbID, "No version available to download.")
            return
        }
        statuses[tmdbID] = DownloadStatus(torrentID: "", tmdbID: tmdbID, phase: .queued, fraction: 0)
        for candidate in candidates.prefix(maxAttempts) {
            do {
                let info = try await service.startDownload(infoHash: candidate.infoHash)
                try? await records.upsert(DownloadRequestData(
                    torrentID: info.id, tmdbID: tmdbID, infoHash: candidate.infoHash,
                    kind: kind, title: title, posterPath: posterPath, requestedAt: now()))
                statuses[tmdbID] = DownloadStatus(from: info, tmdbID: tmdbID)
                startPolling()
                return
            } catch {
                continue   // dead/virus/magnet_error → try the next-best
            }
        }
        statuses[tmdbID] = .failed(tmdbID, "Couldn't start a download. Try another version later.")
    }

    /// One poll pass: refresh progress for every active request. A `.ready` title flips into the
    /// library and its badge clears; a `.failed` one stays so the UI can offer "try another".
    public func refresh() async {
        let results = (try? await poller.poll()) ?? []
        for status in results {
            switch status.phase {
            case .ready:
                await onReady(status.tmdbID)
                statuses[status.tmdbID] = nil
                meta[status.tmdbID] = nil
            case .queued, .downloading, .failed:
                statuses[status.tmdbID] = status
            }
        }
    }

    private func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                if self.statuses.allSatisfy({ if case .failed = $0.value.phase { return true } else { return false } }) {
                    break   // nothing left actively downloading
                }
                try? await Task.sleep(for: self.pollInterval)
            }
            self?.pollTask = nil
        }
    }
}

private extension DownloadStatus {
    /// A failed status with no torrent (a request that never started).
    static func failed(_ tmdbID: Int, _ reason: String) -> DownloadStatus {
        DownloadStatus(torrentID: "", tmdbID: tmdbID, phase: .failed(reason), fraction: 0)
    }
}

/// A poster tile for an in-progress download, rendered in the library grid alongside owned items.
public struct DownloadTile: Identifiable, Sendable, Equatable {
    public let tmdbID: Int
    public let title: String
    public let posterPath: String?
    public let status: DownloadStatus
    public var id: Int { tmdbID }
}
