/// Quality score for a parsed release. Higher is better: resolution dominates, then source tier,
/// then video codec. Releases whose audio can't be decoded on-device (TrueHD) are pushed below
/// every playable release with a large penalty — so the default "Play" picks a version that will
/// actually have sound. Shared by `MediaSource` (library) and `CachedStream` (search).
public func releaseQualityRank(for parsed: ParsedRelease) -> Int {
    resolutionTier(parsed.resolution) * 10_000
        + sourceTier(parsed.source) * 100
        + codecTier(parsed.videoCodec)
        - (isUnplayableAudio(parsed.audioCodec) ? unplayableAudioPenalty : 0)
}

/// Penalty (> the max possible positive rank) so ANY playable release outranks ANY unplayable one,
/// regardless of resolution. Among unplayable-only releases, the video tiers still order them.
let unplayableAudioPenalty = 1_000_000

/// Audio codecs VLCKit can't decode on iOS/tvOS. Only TrueHD (Dolby TrueHD / TrueHD-Atmos, parsed
/// as "TrueHD") is a confirmed hard-fail; everything else — including unknown audio — is treated as
/// playable to avoid demoting good releases. Extend conservatively if more codecs prove unplayable.
func isUnplayableAudio(_ codec: String?) -> Bool {
    codec == "TrueHD"
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
