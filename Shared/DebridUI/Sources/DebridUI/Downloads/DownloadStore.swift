import DebridCore
import Foundation
import Observation

/// Persistence seam for in-progress download requests (DebridCore's `DownloadsStore` conforms).
public protocol DownloadRecording: Sendable {
    func upsert(_ data: DownloadRequestData) async throws
    func all() async throws -> [DownloadRequestData]
    func delete(torrentID: String) async throws
}

/// Polling seam over RD download progress (DebridCore's `DownloadMonitor` conforms).
public protocol DownloadPolling: Sendable {
    func poll() async throws -> [DownloadStatus]
}

/// Deletes an RD torrent — used to cancel a download (DebridCore's `TorrentsClient` conforms).
public protocol DownloadDeleting: Sendable {
    func deleteTorrent(id: String) async throws
}

extension DownloadsStore: DownloadRecording {}
extension DownloadMonitor: DownloadPolling {}
extension TorrentsClient: DownloadDeleting {}

/// App-wide view-model for downloads: starts uncached downloads on the RD seam, persists a record,
/// and surfaces live per-title progress that drives the Home rail, the library strip and the
/// detail-screen status row. A `.ready` poll flips the title into the normal library (via
/// `onReady`) and clears its badge.
///
/// Keyed by `DownloadStatus.storeKey` — the content key, so two episodes of one show track
/// separately, falling back to the torrent id for a foreign download TMDB could not identify.
@MainActor
@Observable
public final class DownloadStore {
    /// Active download status per content key. Absent = nothing in flight (or already in library).
    public private(set) var statuses: [String: DownloadStatus] = [:]

    private let service: DownloadRequesting
    private let records: DownloadRecording
    private let poller: DownloadPolling
    private let deleter: DownloadDeleting
    private let onReady: (DownloadStatus) async -> Void
    private let now: () -> Date
    private let maxAttempts: Int
    private let pollInterval: Duration
    private var pollTask: Task<Void, Never>?

    public init(service: DownloadRequesting,
                records: DownloadRecording,
                poller: DownloadPolling,
                deleter: DownloadDeleting,
                onReady: @escaping (DownloadStatus) async -> Void = { _ in },
                pollInterval: Duration = .seconds(5),
                now: @escaping () -> Date = Date.init,
                maxAttempts: Int = 6) {
        self.service = service; self.records = records; self.poller = poller; self.deleter = deleter
        self.onReady = onReady; self.pollInterval = pollInterval; self.now = now
        self.maxAttempts = maxAttempts
    }

    /// Cancel an in-flight (or stalled) download: delete the RD torrent, drop the persisted record,
    /// and clear the badge. Safe to call for a request that never started (no torrent yet).
    public func cancel(contentKey: String) async {
        let torrentID = statuses[contentKey]?.torrentID
        statuses[contentKey] = nil
        if let torrentID, !torrentID.isEmpty {
            try? await deleter.deleteTorrent(id: torrentID)
            try? await records.delete(torrentID: torrentID)
        }
    }

    public func status(forContentKey key: String) -> DownloadStatus? { statuses[key] }

    /// In-progress downloads (queued/downloading) as poster tiles. Failed and ready ones are
    /// excluded — failed surfaces on Detail, ready becomes a real library item.
    public var activeTiles: [DownloadTile] {
        statuses.values.compactMap { status in
            switch status.phase {
            case .queued, .downloading:
                return DownloadTile(tmdbID: status.tmdbID,
                                    title: status.title.isEmpty ? "Downloading…" : status.title,
                                    posterPath: status.posterPath, status: status)
            case .ready, .failed:
                return nil
            }
        }
        .sorted { $0.status.storeKey < $1.status.storeKey }
    }

    /// Seed badges from persisted records (call at sign-in) so an in-flight download survives an
    /// app restart, then resume polling.
    public func loadActive() async {
        let active = (try? await records.all()) ?? []
        for r in active {
            let key = r.contentKey.isEmpty ? "torrent:\(r.torrentID)" : r.contentKey
            guard statuses[key] == nil else { continue }
            statuses[key] = DownloadStatus(torrentID: r.torrentID, contentKey: r.contentKey,
                                           tmdbID: r.tmdbID, phase: .queued, fraction: 0,
                                           title: r.title, posterPath: r.posterPath)
        }
        if !active.isEmpty { startPolling() }
    }

    /// Start a background download for `contentKey`, trying the ranked candidates in order until
    /// one starts (each terminal failure self-skips, mirroring the instant add's fallback).
    public func request(contentKey: String, tmdbID: Int, title: String, kind: MediaKind,
                        candidates: [CachedStream], posterPath: String? = nil) async {
        guard !candidates.isEmpty else {
            statuses[contentKey] = .failed(contentKey, tmdbID, "No version available to download.")
            return
        }
        statuses[contentKey] = DownloadStatus(torrentID: "", contentKey: contentKey, tmdbID: tmdbID,
                                              phase: .queued, fraction: 0,
                                              title: title, posterPath: posterPath)
        var sawBlocked = false
        for candidate in candidates.prefix(maxAttempts) {
            do {
                let info = try await service.startDownload(infoHash: candidate.infoHash)
                try? await records.upsert(DownloadRequestData(
                    torrentID: info.id, contentKey: contentKey, tmdbID: tmdbID,
                    infoHash: candidate.infoHash,
                    kind: kind, title: title, posterPath: posterPath, requestedAt: now()))
                statuses[contentKey] = DownloadStatus(from: info, contentKey: contentKey,
                                                      tmdbID: tmdbID, title: title,
                                                      posterPath: posterPath)
                startPolling()
                return
            } catch RDAddError.blocked {
                sawBlocked = true   // RD refused it as copyright-flagged — other versions likely too
                continue
            } catch {
                continue            // dead/virus/magnet_error → try the next-best
            }
        }
        statuses[contentKey] = .failed(contentKey, tmdbID, sawBlocked
            ? "Real‑Debrid blocked this title — its torrents are flagged for copyright, so none can be added."
            : "Couldn't start a download. Try another version later.")
    }

    /// One poll pass: refresh progress for every active download. A `.ready` title flips into the
    /// library and its badge clears; a `.failed` one stays so the UI can offer "try another".
    public func refresh() async {
        let results = (try? await poller.poll()) ?? []
        for status in results { await apply(status) }
    }

    /// Test hook: apply monitor results without a poller.
    func applyForTest(_ results: [DownloadStatus]) async {
        for status in results { await apply(status) }
    }

    private func apply(_ status: DownloadStatus) async {
        switch status.phase {
        case .ready:
            statuses[status.storeKey] = nil
            await onReady(status)
        case .queued, .downloading, .failed:
            statuses[status.storeKey] = status
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
    static func failed(_ contentKey: String, _ tmdbID: Int, _ reason: String) -> DownloadStatus {
        DownloadStatus(torrentID: "", contentKey: contentKey, tmdbID: tmdbID,
                       phase: .failed(reason), fraction: 0)
    }
}

/// A poster tile for an in-progress download, rendered in the Home rail and the library grid.
public struct DownloadTile: Identifiable, Sendable, Equatable {
    public let tmdbID: Int
    public let title: String
    public let posterPath: String?
    public let status: DownloadStatus
    public var id: String { status.storeKey }
}
