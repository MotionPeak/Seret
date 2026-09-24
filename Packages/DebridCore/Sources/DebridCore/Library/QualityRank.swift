import Foundation

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

/// A recording made in a cinema, or a pre-release screener, as `FilenameParser` names them.
///
/// These never take the Hebrew-subtitle boost. Hebrew subtitles are routinely made for exactly
/// these copies of a new release, and "Hebrew always on top" would otherwise put a camcorder
/// recording at the head of the list.
func isTheatreSource(_ source: String?) -> Bool {
    guard let source else { return false }
    return ["CAM", "CAMRIP", "HDCAM", "HD-CAM", "HDTS", "HD-TS", "TELESYNC", "TELECINE", "SCREENER"]
        .contains(source.uppercased())
}

/// The same question asked of a raw release name, for the tags `FilenameParser` does not name:
/// `TS`, `TC`, `HDTC`, `SCR`, `DVDSCR`, `HQCAM`, `PDVD`. Only what follows the year (or the
/// episode) is read, so a film called "Cam" is not a camcorder copy, and a `.ts` extension is a
/// container, not a telesync.
func isTheatreRelease(named name: String) -> Bool {
    let stem = FilenameParser.stripExtension(name)
    let ns = stem as NSString
    let whole = NSRange(location: 0, length: ns.length)
    let start = TheatreTags.titleEnd.firstMatch(in: stem, range: whole).map { $0.range.upperBound } ?? 0
    let tail = NSRange(location: start, length: ns.length - start)
    return TheatreTags.tag.firstMatch(in: stem, range: tail) != nil
}

private enum TheatreTags {
    /// The end of the title: the first year or episode marker. Tags come after it.
    static let titleEnd = try! NSRegularExpression(
        pattern: #"(?<![0-9])(?:19|20)[0-9]{2}(?![0-9])|(?<![A-Za-z0-9])S[0-9]{1,2}E[0-9]{1,3}"#,
        options: [.caseInsensitive])

    static let tag = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9])(?:cam|cam-?rip|hd-?cam|hq-?cam|ts|hd-?ts|telesync|pdvd|pre-?dvd|tc|hd-?tc|telecine|scr|screener|dvd-?scr|bd-?scr|web-?scr)(?![A-Za-z0-9])"#,
        options: [.caseInsensitive])
}
