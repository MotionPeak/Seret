import Foundation

/// The debrid services Seret can talk to. Torrent ids and playable-link handles carry enough of
/// their origin to be routed back to the provider that issued them, with no extra stored field.
public enum DebridProvider: String, Codable, Sendable, CaseIterable, Hashable {
    case realDebrid, torBox

    public var displayName: String {
        switch self {
        case .realDebrid: return "Real-Debrid"
        case .torBox: return "TorBox"
        }
    }

    /// TorBox torrent ids are namespaced `tb:<id>`; anything else is a Real-Debrid id.
    public static func of(torrentID: String) -> DebridProvider {
        torrentID.hasPrefix("tb:") ? .torBox : .realDebrid
    }

    /// TorBox playable-link handles are `torbox://<torrentID>/<fileID>`; anything else is an RD
    /// restricted link.
    public static func of(link: String) -> DebridProvider {
        link.hasPrefix("torbox://") ? .torBox : .realDebrid
    }
}

/// The result of listing an account: its torrents, plus which providers could not be reached.
/// A caller keeps the cached titles of an unavailable provider instead of treating them as removed.
public struct TorrentListing: Sendable, Equatable {
    public let torrents: [Torrent]
    public let unavailable: Set<DebridProvider>

    public init(torrents: [Torrent], unavailable: Set<DebridProvider> = []) {
        self.torrents = torrents
        self.unavailable = unavailable
    }
}
