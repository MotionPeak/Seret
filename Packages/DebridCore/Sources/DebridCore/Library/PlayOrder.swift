import Foundation

/// How Play chooses between versions of one title, decided by the language it is spoken in.
///
/// The owner's rules (2026-10-23): a film he understands opens on the fastest REAL picture —
/// the 2160p version with the lowest bitrate, else 1080p — and Hebrew subtitles do not count. A
/// foreign film opens on the version whose Hebrew lines up best, then the same picture rules.
public enum PlayPolicy: Sendable, Equatable {
    /// TMDB has not said. Hebrew does not count, because the guards that keep a dub or a
    /// cinema recording from winning on its subtitles cannot run without the film's language.
    case unknownLanguage
    /// English or Hebrew: no subtitles needed.
    case understood
    /// Anything else: Hebrew subtitles come first.
    case foreign

    public init(originalLanguage: String?) {
        switch LanguageCode.normalize(originalLanguage) {
        case nil: self = .unknownLanguage
        case "en", "he": self = .understood
        default: self = .foreign
        }
    }
}

/// Lowest bitrate a release may have and still be the picture its resolution claims, in
/// megabits a second. A 4K stream from Netflix or Apple runs at 8–25, and AI upscales sit well
/// under 6. At 1080p a fake is rare and a small encode is still real 1080p: the owner's library
/// holds plenty at 1.5–2.5 Mbps, and a higher floor handed Play a 720p file over them.
func genuineFloorMbps(resolution: String?) -> Double? {
    switch resolution {
    case "2160p": return 6
    case "1080p": return 1.5
    case "720p": return 0.8
    default: return nil
    }
}

/// A length to judge a bitrate by when the real one is not known — an episode, or a film before
/// TMDB answered.
private func assumedMinutes(for shape: ReleaseShape) -> Int {
    shape == .movie ? 100 : 40
}

/// What a version weighs per playable file — a season pack per episode — or nil when that cannot
/// be known (no size, or a pack whose episode count is unknown).
func bytesPerFile(_ bytes: Int?, shape: ReleaseShape) -> Int? {
    guard let bytes, bytes > 0 else { return nil }
    switch shape {
    case .movie, .episode: return bytes
    case .seasonPack(let episodes):
        guard let episodes, episodes > 0 else { return nil }
        return bytes / episodes
    }
}

/// Whether a version cannot be trusted to be the picture it claims: its name says it was
/// manufactured, it is a cinema recording, or it is too thin for its resolution.
///
/// Thinness is a bitrate, over the film's runtime when that is known and a typical length when it
/// is not. Unknown size or resolution: nothing to judge, so not suspect.
func isSuspectPicture(_ parsed: ParsedRelease, bytes: Int?, shape: ReleaseShape,
                      runtimeMinutes: Int?, theatreCopy: Bool) -> Bool {
    if parsed.isUpscaled || theatreCopy { return true }
    if !parsed.isTV && isTheatreSource(parsed.source) { return true }
    guard let perFile = bytesPerFile(bytes, shape: shape),
          let floor = genuineFloorMbps(resolution: parsed.resolution) else { return false }
    let known = shape == .movie ? runtimeMinutes.flatMap { $0 > 0 ? $0 : nil } : nil
    let minutes = known ?? assumedMinutes(for: shape)
    return Double(perFile) * 8 / (Double(minutes) * 60) / 1_000_000 < floor
}

/// One version, reduced to what Play's order compares. Built by `MediaSource` and `CachedStream`
/// so both lists follow the same rules.
struct PlayOrderKey {
    /// Search results only — original-language audio before a dub (see `audioTier`).
    let audioTier: Int
    /// VLCKit cannot decode the audio: it would play silently.
    let mute: Bool
    let suspect: Bool
    /// The Hebrew-subtitle tier, lower first; constant unless the policy is `.foreign`.
    let hebrew: Int
    let resolution: Int
    /// Bytes per playable file. Lower first: the lightest real version starts and skips fastest.
    let weight: Int?
    let quality: Int

    /// `true` when `self` plays before `other`, `false` when after, nil when they tie.
    func precedes(_ other: PlayOrderKey) -> Bool? {
        // The film's own language before a dub, then playable audio: a release that plays
        // silently loses at any resolution, but never lifts a dub over the original.
        if audioTier != other.audioTier { return audioTier < other.audioTier }
        if mute != other.mute { return other.mute }
        // Real before manufactured, above Hebrew: an upscale never wins on its subtitles.
        if suspect != other.suspect { return other.suspect }
        if hebrew != other.hebrew { return hebrew < other.hebrew }
        if resolution != other.resolution { return resolution > other.resolution }
        switch (weight, other.weight) {
        case let (a?, b?) where a != b: return a < b
        case (_?, nil): return true
        case (nil, _?): return false
        default: break
        }
        if quality != other.quality { return quality > other.quality }
        return nil
    }
}

extension PlayPolicy {
    /// The Hebrew term as this policy counts it.
    func hebrewTier(_ evidence: SubtitleEvidence?, parsed: ParsedRelease, originalLanguage: String?) -> Int {
        guard self == .foreign else { return HebrewSubtitles.none.rawValue }
        return hebrewBoostTier(evidence, parsed: parsed, originalLanguage: originalLanguage)
    }
}
