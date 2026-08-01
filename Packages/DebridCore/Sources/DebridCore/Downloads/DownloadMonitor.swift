#if canImport(SwiftData)
import Foundation

/// Minimal seam over RD torrent info, so the monitor is testable without the network.
public protocol DownloadInfoProviding: Sendable {
    func info(id: String) async throws -> TorrentInfo
}

/// Lists the account's torrents — the source of truth for what is downloading.
public protocol DownloadListing: Sendable {
    func torrents(page: Int, limit: Int) async throws -> [Torrent]
}

extension TorrentsClient: DownloadInfoProviding {}
extension TorrentsClient: DownloadListing {}

/// Reports what Real-Debrid is currently downloading.
///
/// RD's own torrent list is the source of truth, so a download started on another device, in DMM,
/// or RD's web UI appears here too. Identity comes from the local `DownloadRequest` when Seret
/// started the download — that record holds the exact tmdbID and episode key — and otherwise from
/// the resolver, which can only guess from the release name.
///
/// Holds one `ETAEstimator` per torrent so the reported remaining time is smoothed across polls
/// rather than recomputed from RD's jumpy instantaneous speed.
public actor DownloadMonitor {
    private let lister: any DownloadListing
    private let store: DownloadsStore
    private let resolver: any DownloadIdentityResolving
    private let now: @Sendable () -> Date
    private let pageLimit: Int
    private var estimators: [String: ETAEstimator] = [:]
    /// Torrent ids that were active on the previous poll. A torrent that drops out of this set has
    /// finished, failed, or been deleted — that transition is announced exactly once.
    private var previouslyActive: Set<String> = []

    /// Test hook: estimator state must not accumulate across completed downloads.
    var trackedEstimatorCount: Int { estimators.count }

    /// RD statuses that mean the torrent is still working toward `downloaded`. `compressing` and
    /// `uploading` are RD's post-download processing — still "in flight" from the user's side.
    static let activeStatuses: Set<String> = ["queued", "magnet_conversion",
                                              "waiting_files_selection", "downloading",
                                              "compressing", "uploading"]

    public init(lister: any DownloadListing, store: DownloadsStore,
                resolver: any DownloadIdentityResolving,
                now: @escaping @Sendable () -> Date = Date.init,
                pageLimit: Int = 100) {
        self.lister = lister
        self.store = store
        self.resolver = resolver
        self.now = now
        self.pageLimit = pageLimit
    }

    /// One pass. Returns a status for every torrent RD is currently working on, plus a one-shot
    /// terminal status for anything that stopped being active since the last poll.
    @discardableResult
    public func poll() async throws -> [DownloadStatus] {
        let list = try await lister.torrents(page: 1, limit: pageLimit)
        let byID = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let records = Dictionary((try await store.all()).map { ($0.torrentID, $0) },
                                 uniquingKeysWith: { first, _ in first })

        var statuses: [DownloadStatus] = []
        var active: Set<String> = []

        for torrent in list where Self.activeStatuses.contains(torrent.status) {
            active.insert(torrent.id)
            let identity = await identify(torrent, record: records[torrent.id])
            var estimator = estimators[torrent.id] ?? ETAEstimator()
            let eta = estimator.observe(fraction: torrent.progress / 100, totalBytes: torrent.bytes,
                                        reportedSpeed: torrent.speed, at: now())
            estimators[torrent.id] = estimator
            statuses.append(DownloadStatus(from: torrent,
                                           contentKey: identity?.contentKey ?? "",
                                           tmdbID: identity?.tmdbID ?? 0,
                                           title: identity?.title ?? "",
                                           posterPath: identity?.posterPath,
                                           secondsRemaining: eta))
        }

        // Anything that was active and no longer is has reached a terminal state. Recorded
        // requests RD no longer lists at all are swept the same way, so a torrent deleted
        // elsewhere cannot leak its record forever.
        let settled = previouslyActive.subtracting(active)
            .union(records.keys.filter { !active.contains($0) })
        for id in settled.sorted() {
            let record = records[id]
            let listed = byID[id]
            // A vanished torrent has no `Torrent` to resolve from, so fall back to the record.
            let identity: DownloadIdentity?
            if let listed {
                identity = await identify(listed, record: record)
            } else {
                identity = record.flatMap(Self.identity(fromRecord:))
            }

            if let listed {
                statuses.append(DownloadStatus(from: listed,
                                               contentKey: identity?.contentKey ?? "",
                                               tmdbID: identity?.tmdbID ?? 0,
                                               title: identity?.title ?? "",
                                               posterPath: identity?.posterPath))
            } else {
                // RD no longer lists it at all — deleted from the account.
                statuses.append(DownloadStatus(torrentID: id,
                                               contentKey: identity?.contentKey ?? "",
                                               tmdbID: identity?.tmdbID ?? 0,
                                               phase: .failed("removed"), fraction: 0,
                                               title: identity?.title ?? "",
                                               posterPath: identity?.posterPath))
            }
            estimators[id] = nil
            if record != nil { try? await store.delete(torrentID: id) }
        }

        previouslyActive = active
        return statuses
    }

    /// A record we wrote when starting the download beats the resolver every time: it holds the
    /// exact tmdbID and episode key, where the resolver only infers from a release name.
    private func identify(_ torrent: Torrent,
                          record: DownloadRequestData?) async -> DownloadIdentity? {
        if let fromRecord = record.flatMap(Self.identity(fromRecord:)) { return fromRecord }
        return await resolver.identity(filename: torrent.filename, infoHash: torrent.hash)
    }

    /// A record only counts as identity once it actually carries a key — rows written before
    /// `contentKey` existed have an empty one, and must fall through to the resolver.
    private static func identity(fromRecord r: DownloadRequestData) -> DownloadIdentity? {
        guard !r.contentKey.isEmpty else { return nil }
        return DownloadIdentity(contentKey: r.contentKey, tmdbID: r.tmdbID, kind: r.kind,
                                title: r.title, posterPath: r.posterPath)
    }
}
#endif
