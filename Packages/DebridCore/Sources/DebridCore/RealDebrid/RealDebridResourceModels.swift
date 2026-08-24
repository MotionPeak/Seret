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
    /// Download rate in bytes/sec. RD sends this only while `status == "downloading"`.
    public let speed: Int?
    /// Peers currently serving the torrent. RD sends this only while downloading; 0 means
    /// nothing is available to download from yet.
    public let seeders: Int?

    public init(id: String, filename: String, hash: String, bytes: Int, host: String,
                progress: Double, status: String, added: String, links: [String],
                ended: String? = nil, speed: Int? = nil, seeders: Int? = nil) {
        self.id = id; self.filename = filename; self.hash = hash; self.bytes = bytes
        self.host = host; self.progress = progress; self.status = status
        self.added = added; self.links = links; self.ended = ended
        self.speed = speed; self.seeders = seeders
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

    /// Whether Real-Debrid selected this file for download (it encodes this as 1/0).
    public var isSelected: Bool { selected == 1 }
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
    /// ISO-8601 date the torrent was added to RD. Nil from `/torrents/info/{id}` (which omits
    /// it); `TorrentsClient.allTorrentInfos()` carries it over from the `/torrents` list.
    public let added: String?
    /// Download rate in bytes/sec. RD sends this only while `status == "downloading"`.
    public let speed: Int?
    /// Peers currently serving the torrent. RD sends this only while downloading; 0 means
    /// nothing is available to download from yet.
    public let seeders: Int?

    public init(id: String, filename: String, hash: String, bytes: Int, progress: Double,
                status: String, files: [TorrentFile], links: [String], added: String? = nil,
                speed: Int? = nil, seeders: Int? = nil) {
        self.id = id; self.filename = filename; self.hash = hash; self.bytes = bytes
        self.progress = progress; self.status = status; self.files = files; self.links = links
        self.added = added; self.speed = speed; self.seeders = seeders
    }
}

public extension TorrentInfo {
    /// Real-Debrid returns `links` in the order of the *selected* files. Pairs each
    /// `isSelected` file with its restricted link by that order. If the counts ever
    /// disagree (an unexpected API response), pairing is best-effort — `zip` truncates
    /// to the shorter side.
    func selectedFilesWithLinks() -> [(file: TorrentFile, link: String)] {
        let selected = files.filter { $0.isSelected }
        return zip(selected, links).map { (file: $0, link: $1) }
    }

    /// Recognised playable video container extensions (shared across selection + playback).
    static let videoExtensions: Set<String> = ["mkv", "mp4", "avi", "m4v", "mov", "ts", "wmv"]

    private static func isVideo(_ path: String) -> Bool {
        videoExtensions.contains(URL(fileURLWithPath: path).pathExtension.lowercased())
    }

    /// The largest *selected video* file paired with its restricted link — the thing
    /// you actually want to play. Returns nil if there's no selected video file.
    func primaryVideoFile() -> (file: TorrentFile, link: String)? {
        selectedFilesWithLinks()
            .filter { Self.isVideo($0.file.path) }
            .max { $0.file.bytes < $1.file.bytes }
    }

    /// The selected video file for ONE episode, paired with its restricted link.
    ///
    /// `primaryVideoFile()` answers "the largest video file", which is right for a movie and
    /// wrong for a season pack: it returns whichever episode happens to be biggest. Playback
    /// used it for episodes too, so clicking E3 played the double-length opener while recording
    /// progress under E3's key.
    ///
    /// Matching is on the FILE's own parsed name, not the torrent's — a pack is named for the
    /// season, only its files name episodes. `season: nil` matches on episode number alone (a
    /// file named "Episode 2.mkv" carries no season); a non-nil season must match when the file
    /// states one, so a S01–S02 pack never confuses S01E03 with S02E03.
    ///
    /// Returns nil when the episode isn't in this torrent — deliberately, because a consolation
    /// file IS the defect. Nothing is better than the wrong episode.
    ///
    /// Among the files that DO name the episode, the largest wins. A pack routinely carries more
    /// than one file for an episode — a sample clip, a featurette, a re-encode — and `videoFileIDs`
    /// selects every video file, so RD returns a link for each. Taking the first match therefore
    /// handed playback whichever one RD happened to list first: a 40 MB `Sample/` clip beat the
    /// real 2 GB episode, and the episode played for thirty seconds and stopped.
    func videoFile(forSeason season: Int?, episode: Int) -> (file: TorrentFile, link: String)? {
        let parser = FilenameParser()
        return selectedFilesWithLinks()
            .filter { Self.isVideo($0.file.path) }
            .filter { pair in
                let parsed = parser.parse(pair.file.path)
                guard parsed.episode == episode else { return false }
                // A file that names no season belongs to whatever season was asked for.
                guard let season, let fileSeason = parsed.season else { return true }
                return fileSeason == season
            }
            // Deterministic: equal sizes fall back to file id, so one pack always resolves the
            // same way rather than following RD's listing order.
            .max { a, b in
                a.file.bytes != b.file.bytes ? a.file.bytes < b.file.bytes : a.file.id < b.file.id
            }
    }

    /// File ids of the torrent's video files — what to pass to `selectFiles` so RD doesn't
    /// also "select" junk (thumbnails, .nfo, .sqlite metadata). Selecting non-video files
    /// breaks the file↔link pairing (RD only returns links for the real media). Empty → the
    /// caller should fall back to "all".
    func videoFileIDs() -> [Int] {
        files.filter { Self.isVideo($0.path) }.map(\.id)
    }
}

/// Response from `POST /torrents/addMagnet` (also `addTorrent`).
public struct AddMagnetResponse: Decodable, Sendable, Equatable {
    public let id: String
    public let uri: String?

    public init(id: String, uri: String? = nil) {
        self.id = id; self.uri = uri
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
