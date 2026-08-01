import Foundation

/// A Sendable snapshot of where a requested download is, derived purely from an RD torrent.
public struct DownloadStatus: Sendable, Equatable, Identifiable {
    public enum Phase: Sendable, Equatable {
        case queued, downloading, ready, failed(String)
    }
    public let torrentID: String
    /// What this download is *for* — see `DownloadKey`. Empty for statuses built before a torrent
    /// exists (a request that has not started yet), or when identity could not be resolved.
    public let contentKey: String
    public let tmdbID: Int
    public let phase: Phase
    public let fraction: Double   // 0...1
    /// Total size in bytes of the selected files, straight from RD.
    public let bytesTotal: Int
    /// RD's instantaneous rate. Nil unless the torrent is actively downloading.
    public let speedBytesPerSecond: Int?
    /// Peers currently serving the torrent. Zero means nothing to download from yet.
    public let seeders: Int?
    /// Smoothed estimate from `ETAEstimator`. Nil when the rate is unknown — callers must show a
    /// qualitative state ("Waiting for peers") rather than substituting a number.
    public let secondsRemaining: TimeInterval?
    /// Display title. Carried here rather than looked up, because a download Seret did not start
    /// has no local record and is not in the library.
    public let title: String
    public let posterPath: String?

    public var id: String { torrentID }

    /// The key `DownloadStore` files this status under. Prefers the content key so a status
    /// survives the torrent being retried under a different id; falls back to the torrent id for
    /// a foreign download whose release name TMDB could not match, so two of those never collide.
    public var storeKey: String {
        contentKey.isEmpty ? "torrent:\(torrentID)" : contentKey
    }

    /// RD statuses that mean the download will never finish.
    static let terminalStatuses: Set<String> = ["error", "magnet_error", "dead", "virus"]
    /// RD statuses before bytes start flowing.
    static let queuedStatuses: Set<String> = ["queued", "magnet_conversion", "waiting_files_selection"]

    /// Classify an RD status string. Shared by both inits so the list and detail endpoints can
    /// never disagree about what a status means.
    static func phase(forRDStatus status: String) -> Phase {
        if status == "downloaded" { return .ready }
        if terminalStatuses.contains(status) { return .failed(status) }
        if queuedStatuses.contains(status) { return .queued }
        return .downloading   // includes RD's post-download "compressing" / "uploading"
    }

    public init(from info: TorrentInfo, contentKey: String = "", tmdbID: Int,
                title: String = "", posterPath: String? = nil,
                secondsRemaining: TimeInterval? = nil) {
        self.init(torrentID: info.id, contentKey: contentKey, tmdbID: tmdbID,
                  phase: Self.phase(forRDStatus: info.status),
                  fraction: max(0, min(1, info.progress / 100)),
                  bytesTotal: info.bytes, speedBytesPerSecond: info.speed, seeders: info.seeders,
                  secondsRemaining: secondsRemaining, title: title, posterPath: posterPath)
    }

    public init(from torrent: Torrent, contentKey: String = "", tmdbID: Int,
                title: String = "", posterPath: String? = nil,
                secondsRemaining: TimeInterval? = nil) {
        self.init(torrentID: torrent.id, contentKey: contentKey, tmdbID: tmdbID,
                  phase: Self.phase(forRDStatus: torrent.status),
                  fraction: max(0, min(1, torrent.progress / 100)),
                  bytesTotal: torrent.bytes, speedBytesPerSecond: torrent.speed,
                  seeders: torrent.seeders,
                  secondsRemaining: secondsRemaining, title: title, posterPath: posterPath)
    }

    public init(torrentID: String, contentKey: String = "", tmdbID: Int, phase: Phase,
                fraction: Double, bytesTotal: Int = 0, speedBytesPerSecond: Int? = nil,
                seeders: Int? = nil, secondsRemaining: TimeInterval? = nil,
                title: String = "", posterPath: String? = nil) {
        self.torrentID = torrentID; self.contentKey = contentKey; self.tmdbID = tmdbID
        self.phase = phase; self.fraction = fraction; self.bytesTotal = bytesTotal
        self.speedBytesPerSecond = speedBytesPerSecond; self.seeders = seeders
        // A queued torrent has no meaningful rate, so never claim one.
        self.secondsRemaining = phase == .queued ? nil : secondsRemaining
        self.title = title; self.posterPath = posterPath
    }
}
