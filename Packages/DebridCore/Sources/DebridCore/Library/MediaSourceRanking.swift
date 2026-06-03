/// Quality ranking for picking the default ("best") source and ordering the Versions list.
/// Pure and deterministic; tiers match `FilenameParser`'s canonical normalized tokens.
public extension MediaSource {
    /// Higher is better. Resolution dominates, then source tier, then video codec.
    var qualityRank: Int {
        Self.resolutionTier(parsed.resolution) * 10_000
            + Self.sourceTier(parsed.source) * 100
            + Self.codecTier(parsed.videoCodec)
    }

    // Tier helpers are implementation details of `qualityRank` — not module API.
    private static func resolutionTier(_ r: String?) -> Int {
        switch r {                 // ParsedRelease stores resolution lowercased
        case "2160p": return 4
        case "1080p": return 3
        case "720p": return 2
        case "480p": return 1
        default: return 0
        }
    }

    private static func sourceTier(_ s: String?) -> Int {
        switch s {                 // FilenameParser.normalizeSource canonical forms
        case "REMUX": return 7
        case "BluRay": return 6
        case "WEB-DL": return 5
        case "WEBRip": return 4
        case "BDRip": return 3
        case "HDTV": return 2
        case "HDRip", "DVDRip": return 1
        default: return 0
        }
    }

    private static func codecTier(_ c: String?) -> Int {
        switch c {                 // HEVC/x265/h265 are H.265 aliases the parser may emit; AVC/x264/h264 are H.264
        case "HEVC", "x265", "h265": return 2
        case "AVC", "x264", "h264": return 1
        default: return 0
        }
    }
}

public extension Array where Element == MediaSource {
    /// Sources best-first. Deterministic: ties break by torrentID, then fileID.
    func bestFirst() -> [MediaSource] {
        sorted { a, b in
            if a.qualityRank != b.qualityRank { return a.qualityRank > b.qualityRank }
            if a.torrentID != b.torrentID { return a.torrentID < b.torrentID }
            return (a.fileID ?? -1) < (b.fileID ?? -1)   // nil fileID (non-pack torrent) sorts before any real fileID
        }
    }

    /// The single best source, or nil when empty.
    var best: MediaSource? { bestFirst().first }
}
