import Foundation

/// A Sendable snapshot of where a requested download is, derived purely from an RD `TorrentInfo`.
public struct DownloadStatus: Sendable, Equatable, Identifiable {
    public enum Phase: Sendable, Equatable {
        case queued, downloading, ready, failed(String)
    }
    public let torrentID: String
    public let tmdbID: Int
    public let phase: Phase
    public let fraction: Double   // 0...1

    public var id: String { torrentID }

    /// RD statuses that mean the download will never finish.
    static let terminalStatuses: Set<String> = ["error", "magnet_error", "dead", "virus"]
    /// RD statuses before bytes start flowing.
    static let queuedStatuses: Set<String> = ["queued", "magnet_conversion", "waiting_files_selection"]

    public init(from info: TorrentInfo, tmdbID: Int) {
        self.torrentID = info.id
        self.tmdbID = tmdbID
        self.fraction = max(0, min(1, info.progress / 100))
        if info.status == "downloaded" {
            self.phase = .ready
        } else if Self.terminalStatuses.contains(info.status) {
            self.phase = .failed(info.status)
        } else if Self.queuedStatuses.contains(info.status) {
            self.phase = .queued
        } else {
            self.phase = .downloading
        }
    }

    public init(torrentID: String, tmdbID: Int, phase: Phase, fraction: Double) {
        self.torrentID = torrentID; self.tmdbID = tmdbID; self.phase = phase; self.fraction = fraction
    }
}
