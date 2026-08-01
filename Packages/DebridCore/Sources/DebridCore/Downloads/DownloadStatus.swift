import Foundation

/// A Sendable snapshot of where a requested download is, derived purely from an RD `TorrentInfo`.
public struct DownloadStatus: Sendable, Equatable, Identifiable {
    public enum Phase: Sendable, Equatable {
        case queued, downloading, ready, failed(String)
    }
    public let torrentID: String
    /// What this download is *for* — see `DownloadKey`. Empty for statuses built before a torrent
    /// exists (a request that has not started yet).
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

    public var id: String { torrentID }

    /// RD statuses that mean the download will never finish.
    static let terminalStatuses: Set<String> = ["error", "magnet_error", "dead", "virus"]
    /// RD statuses before bytes start flowing.
    static let queuedStatuses: Set<String> = ["queued", "magnet_conversion", "waiting_files_selection"]

    public init(from info: TorrentInfo, contentKey: String = "", tmdbID: Int,
                secondsRemaining: TimeInterval? = nil) {
        self.torrentID = info.id
        self.contentKey = contentKey
        self.tmdbID = tmdbID
        self.fraction = max(0, min(1, info.progress / 100))
        self.bytesTotal = info.bytes
        self.speedBytesPerSecond = info.speed
        self.seeders = info.seeders
        if info.status == "downloaded" {
            self.phase = .ready
        } else if Self.terminalStatuses.contains(info.status) {
            self.phase = .failed(info.status)
        } else if Self.queuedStatuses.contains(info.status) {
            self.phase = .queued
        } else {
            self.phase = .downloading
        }
        // A queued torrent has no meaningful rate, so never claim one.
        self.secondsRemaining = self.phase == .queued ? nil : secondsRemaining
    }

    public init(torrentID: String, contentKey: String = "", tmdbID: Int, phase: Phase,
                fraction: Double, bytesTotal: Int = 0, speedBytesPerSecond: Int? = nil,
                seeders: Int? = nil, secondsRemaining: TimeInterval? = nil) {
        self.torrentID = torrentID; self.contentKey = contentKey; self.tmdbID = tmdbID
        self.phase = phase; self.fraction = fraction; self.bytesTotal = bytesTotal
        self.speedBytesPerSecond = speedBytesPerSecond; self.seeders = seeders
        self.secondsRemaining = secondsRemaining
    }
}
