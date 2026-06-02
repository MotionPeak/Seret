import Foundation

/// A torrent in the user's Real-Debrid library (`GET /torrents` item).
public struct Torrent: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let filename: String
    public let hash: String
    public let bytes: Int
    public let host: String
    public let progress: Double
    public let status: String
    public let added: String
    public let links: [String]
    public let ended: String?

    public init(id: String, filename: String, hash: String, bytes: Int, host: String,
                progress: Double, status: String, added: String, links: [String], ended: String? = nil) {
        self.id = id; self.filename = filename; self.hash = hash; self.bytes = bytes
        self.host = host; self.progress = progress; self.status = status
        self.added = added; self.links = links; self.ended = ended
    }
}

/// A file inside a torrent (`GET /torrents/info/{id}` → `files[]`).
public struct TorrentFile: Decodable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let path: String
    public let bytes: Int
    public let selected: Int   // 1 = selected for download, 0 = skipped

    public init(id: Int, path: String, bytes: Int, selected: Int) {
        self.id = id; self.path = path; self.bytes = bytes; self.selected = selected
    }
}

/// Detailed torrent info (`GET /torrents/info/{id}`).
public struct TorrentInfo: Decodable, Sendable, Equatable {
    public let id: String
    public let filename: String
    public let hash: String
    public let bytes: Int
    public let progress: Double
    public let status: String
    public let files: [TorrentFile]
    public let links: [String]

    public init(id: String, filename: String, hash: String, bytes: Int, progress: Double,
                status: String, files: [TorrentFile], links: [String]) {
        self.id = id; self.filename = filename; self.hash = hash; self.bytes = bytes
        self.progress = progress; self.status = status; self.files = files; self.links = links
    }
}

public extension TorrentInfo {
    /// Real-Debrid returns `links` in the order of the *selected* files. Pairs each
    /// selected file (`selected == 1`) with its restricted link by that order.
    func selectedFilesWithLinks() -> [(file: TorrentFile, link: String)] {
        let selected = files.filter { $0.selected == 1 }
        return Array(zip(selected, links).map { (file: $0, link: $1) })
    }

    /// The largest *selected video* file paired with its restricted link — the thing
    /// you actually want to play. Returns nil if there's no selected video file.
    func primaryVideoFile() -> (file: TorrentFile, link: String)? {
        let videoExtensions: Set<String> = ["mkv", "mp4", "avi", "m4v", "mov", "ts", "wmv"]
        return selectedFilesWithLinks()
            .filter { videoExtensions.contains(($0.file.path as NSString).pathExtension.lowercased()) }
            .max { $0.file.bytes < $1.file.bytes }
    }
}

/// A restricted link resolved into a directly-streamable URL (`POST /unrestrict/link`).
public struct UnrestrictedLink: Decodable, Sendable, Equatable {
    public let download: String      // the direct, streamable URL — hand this to the player
    public let filename: String
    public let filesize: Int
    public let mimeType: String?

    public init(download: String, filename: String, filesize: Int, mimeType: String?) {
        self.download = download; self.filename = filename
        self.filesize = filesize; self.mimeType = mimeType
    }
}
