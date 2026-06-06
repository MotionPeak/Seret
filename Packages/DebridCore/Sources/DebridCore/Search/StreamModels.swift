import Foundation

/// What to search for on a `StreamSource`.
public struct StreamQuery: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case movie
        case series(season: Int, episode: Int)
    }
    public let imdbID: String          // e.g. "tt0133093"
    public let kind: Kind
    public let originalLanguage: String? // ISO 639-1, from TMDB; drives ranking

    public init(imdbID: String, kind: Kind, originalLanguage: String?) {
        self.imdbID = imdbID; self.kind = kind; self.originalLanguage = originalLanguage
    }
}

/// Convenience alias so call sites can write `StreamKind` if preferred.
public typealias StreamKind = StreamQuery.Kind

/// One already-cached torrent returned by a `StreamSource`, ready to add to RD.
public struct CachedStream: Sendable, Equatable, Identifiable {
    public let infoHash: String        // 40-hex; what we addMagnet
    public let fileIdx: Int?           // addon's chosen file index hint (may be nil)
    public let rawTitle: String        // the torrent's release name (for parsing/display)
    public let parsed: ParsedRelease   // quality fields from rawTitle
    public let languages: [String]     // detected audio languages (ISO 639-1)
    public let sizeBytes: Int?
    public let sourceName: String?     // e.g. "RD" / addon label

    public var id: String { infoHash }

    /// Higher is better — same formula as the library's `MediaSource`.
    public var qualityRank: Int { releaseQualityRank(for: parsed) }

    public init(infoHash: String, fileIdx: Int?, rawTitle: String, parsed: ParsedRelease,
                languages: [String], sizeBytes: Int?, sourceName: String?) {
        self.infoHash = infoHash; self.fileIdx = fileIdx; self.rawTitle = rawTitle
        self.parsed = parsed; self.languages = languages; self.sizeBytes = sizeBytes
        self.sourceName = sourceName
    }
}
