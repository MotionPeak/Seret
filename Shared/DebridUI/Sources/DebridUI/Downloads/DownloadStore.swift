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
    /// Info-hashes Real-Debrid has refused as copyright-flagged (HTTP 451) this session.
    ///
    /// A 451 is a fact about the HASH, not about the moment, so nothing is learned by asking again.
    /// "Try Another Version" re-runs the same ranked list, and it used to spend its first request
    /// re-confirming the refusal it had just reported — which is why a retry looked like it "got
    /// blocked again" while the version behind it would have started.
    private var blockedHashes: Set<String> = []

    /// Extra delay added to the poll interval after a failure. RD rate-limits, and this loop now
    /// issues a recurring GET /torrents — without backoff a failing account becomes a request
    /// storm.
    private(set) var pollBackoff: Duration = .zero
    private static let maxBackoff: Duration = .seconds(60)

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
        // Two budgets, because the two failures cost different things. A real attempt adds a
        // torrent to the account (and may leave one behind), so those stay capped at `maxAttempts`.
        // A 451 is one request that creates nothing and says nothing about the NEXT candidate — a
        // different torrent, which RD's blocklist has its own opinion about — so it is not a turn.
        // It is still a request, so refusals are bounded too, more loosely.
        var attempts = 0
        var probes = 0
        var blocked = 0
        var failed = 0
        for candidate in candidates {
            guard attempts < maxAttempts, probes < maxAttempts * 2 else { break }
            if blockedHashes.contains(candidate.infoHash) {
                blocked += 1           // already refused this session — skip without asking again
                continue
            }
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
                blockedHashes.insert(candidate.infoHash)
                blocked += 1
                probes += 1
                continue
            } catch {
                attempts += 1
                failed += 1
                continue            // dead/virus/magnet_error → try the next-best
            }
        }
        statuses[contentKey] = .failed(contentKey, tmdbID,
                                       Self.failureMessage(blocked: blocked, failed: failed))
    }

    /// What to tell the viewer when nothing started.
    ///
    /// Only a title whose EVERY tried version was refused is "blocked". One refusal among ordinary
    /// failures used to condemn the whole title ("none can be added") — and then the next retry
    /// started a download, which read as Real-Debrid changing its mind about copyright. It had
    /// not; the other versions had simply failed for reasons of the moment.
    static func failureMessage(blocked: Int, failed: Int) -> String {
        switch (blocked, failed) {
        case (0, _):
            return "Couldn't start a download. Try another version later."
        case (_, 0):
            return "Real‑Debrid refuses every version of this title it was offered — they're flagged for copyright."
        default:
            let refused = blocked == 1 ? "1 version is" : "\(blocked) versions are"
            return "\(refused) flagged for copyright on Real‑Debrid, and the rest couldn't start. Try another version later."
        }
    }

    /// One poll pass: refresh progress for every active download. A `.ready` title flips into the
    /// library and its badge clears; a `.failed` one stays so the UI can offer "try another".
    public func refresh() async {
        do {
            let results = try await poller.poll()
            pollBackoff = .zero          // one good poll clears the penalty
            for status in results { await apply(status) }
        } catch {
            pollBackoff = pollBackoff == .zero ? .seconds(5)
                : min(pollBackoff * 2, Self.maxBackoff)
        }
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
                try? await Task.sleep(for: self.pollInterval + self.pollBackoff)
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
