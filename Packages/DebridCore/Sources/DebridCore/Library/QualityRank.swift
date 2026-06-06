/// Quality score for a parsed release. Higher is better: resolution dominates,
/// then source tier, then video codec. Shared by `MediaSource` (library) and
/// `CachedStream` (search) so both rank identically.
public func releaseQualityRank(for parsed: ParsedRelease) -> Int {
    resolutionTier(parsed.resolution) * 10_000
        + sourceTier(parsed.source) * 100
        + codecTier(parsed.videoCodec)
}

func resolutionTier(_ r: String?) -> Int {
    switch r {                 // ParsedRelease stores resolution lowercased
    case "2160p": return 4
    case "1080p": return 3
    case "720p": return 2
    case "480p": return 1
    default: return 0
    }
}

func sourceTier(_ s: String?) -> Int {
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

func codecTier(_ c: String?) -> Int {
    switch c {                 // H.265 aliases rank above H.264 aliases
    case "HEVC", "x265", "h265": return 2
    case "AVC", "x264", "h264": return 1
    default: return 0
    }
}
