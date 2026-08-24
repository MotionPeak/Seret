import Foundation

public enum MediaKind: String, Sendable, Equatable, Hashable, Codable {
    case movie, show
}

/// A specific playable thing in Real-Debrid: a torrent (and, for packs, a file within it),
/// its restricted link (unrestrict at play time), and the parse used for quality display.
public struct MediaSource: Sendable, Equatable, Hashable, Codable {
    public let torrentID: String
    public let fileID: Int?
    public let restrictedLink: String
    public let parsed: ParsedRelease
    /// Size of this file on disk. Drives size-aware ranking so the Versions list stops
    /// recommending the bloat the search flow now avoids. Optional: snapshots cached before this
    /// existed carry no size, and a missing size ranks neutrally rather than last.
    public let sizeBytes: Int?

    public init(torrentID: String, fileID: Int?, restrictedLink: String, parsed: ParsedRelease,
                sizeBytes: Int? = nil) {
        self.torrentID = torrentID
        self.fileID = fileID
        self.restrictedLink = restrictedLink
        self.parsed = parsed
        self.sizeBytes = sizeBytes
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        torrentID = try c.decode(String.self, forKey: .torrentID)
        fileID = try c.decodeIfPresent(Int.self, forKey: .fileID)
        restrictedLink = try c.decode(String.self, forKey: .restrictedLink)
        parsed = try c.decode(ParsedRelease.self, forKey: .parsed)
        // Absent in snapshots written before size ranking existed — decode to nil rather than
        // failing, which would discard the whole cached library until the next refresh.
        sizeBytes = try c.decodeIfPresent(Int.self, forKey: .sizeBytes)
    }
}

public struct Episode: Sendable, Equatable, Hashable, Identifiable, Codable {
    public let season: Int
    public let number: Int
    /// The copy that plays by default — the best owned one under `bestFirst()`.
    public let source: MediaSource
    /// Every OTHER owned copy of this episode, best-first.
    ///
    /// Modelled as "primary + alternates" rather than turning `source` into an array. The array
    /// form ripples through every call site, the snapshot `Codable`, the reconciler, both apps and
    /// the server DTO, and it forces a force-unwrap or a failable init to express "always at least
    /// one". This keeps `source` exactly as it was, needs no force-unwrap, and lets snapshots
    /// written before alternates existed decode with an empty list.
    public let alternates: [MediaSource]

    public init(season: Int, number: Int, source: MediaSource, alternates: [MediaSource] = []) {
        self.season = season
        self.number = number
        self.source = source
        self.alternates = alternates
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        season = try c.decode(Int.self, forKey: .season)
        number = try c.decode(Int.self, forKey: .number)
        source = try c.decode(MediaSource.self, forKey: .source)
        // Absent in snapshots written before this existed. Decoding to empty rather than failing
        // matters: the snapshot IS the cached library, and a throw would blank it until refresh.
        alternates = try c.decodeIfPresent([MediaSource].self, forKey: .alternates) ?? []
    }

    /// Every owned copy, best-first and never empty — what a Versions list shows, and what lets
    /// the player fall back when a stream goes bad mid-episode.
    public var sources: [MediaSource] { [source] + alternates }

    public var id: String { "s\(season)e\(number)" }
}

public struct Season: Sendable, Equatable, Hashable, Identifiable, Codable {
    public let number: Int
    public let episodes: [Episode]   // sorted by episode number

    public init(number: Int, episodes: [Episode]) {
        self.number = number
        self.episodes = episodes
    }

    public var id: Int { number }
}

/// A top-level library entry: a movie or a show. Metadata fields are nil until TMDB
/// enrichment (Plan 5). A movie carries `sources` (1+); a show carries `seasons`.
public struct MediaItem: Sendable, Equatable, Hashable, Identifiable, Codable {
    public let id: String
    public let kind: MediaKind
    public let title: String
    public let year: Int?
    public let sources: [MediaSource]
    public let seasons: [Season]
    public let tmdbID: Int?
    public let posterPath: String?
    public let backdropPath: String?
    public let overview: String?
    /// When this item entered the RD library (newest torrent's `added` date). Optional so
    /// old cached snapshots (which lack the key) still decode. Powers "Recently Added".
    public let addedAt: Date?

    public init(id: String, kind: MediaKind, title: String, year: Int?,
                sources: [MediaSource], seasons: [Season],
                tmdbID: Int? = nil, posterPath: String? = nil,
                backdropPath: String? = nil, overview: String? = nil,
                addedAt: Date? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.year = year
        self.sources = sources
        self.seasons = seasons
        self.tmdbID = tmdbID
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.overview = overview
        self.addedAt = addedAt
    }
}
