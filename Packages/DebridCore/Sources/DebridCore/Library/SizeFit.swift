import Foundation

/// What a release holds. The size a file *should* weigh depends on it: 25 GB is an ideal film
/// and an absurd single episode.
public enum ReleaseShape: Sendable, Equatable {
    case movie
    case episode
    /// A whole season in one torrent. `episodes` lets the size be judged per episode; without it
    /// there is nothing to compare a pack against.
    case seasonPack(episodes: Int?)

    /// Derived from a parsed release name: an episode number means one episode, a season with no
    /// episode number means a pack, anything else is a film.
    public static func of(_ parsed: ParsedRelease, episodes: Int? = nil) -> ReleaseShape {
        if parsed.episode != nil { return .episode }
        if parsed.season != nil { return .seasonPack(episodes: episodes) }
        return .movie
    }
}

/// How well a file's size fits its resolution and shape. Ordered, so `.ideal > .near > .far`.
public enum SizeFit: Int, Sendable, Equatable, Comparable {
    case far = 0
    case near = 1
    case ideal = 2

    public static func < (a: SizeFit, b: SizeFit) -> Bool { a.rawValue < b.rawValue }
}

/// Score a file's size against what its resolution and shape should reasonably weigh.
///
/// Ranking treated "bigger" as "better" outright — and since `REMUX` is the top source tier, the
/// default pick for a 4K title was the largest untranscoded Blu-ray on offer, routinely 70–80 GB.
/// Those open slowly, skip roughly, and press hard on an Apple TV's memory.
///
/// This is deliberately 3-valued rather than a continuous score: the inputs are a parsed
/// resolution string and a torrent's advertised byte count, which do not support finer precision.
/// It also means that when *every* candidate is oversized they all tie here and the existing
/// quality ordering still decides — nothing becomes unplayable, it just stops being the default.
public func sizeFit(bytes: Int?, resolution: String?, shape: ReleaseShape) -> SizeFit {
    // Unknown size is neutral: it must not beat a known-good file, nor lose to known bloat.
    guard let bytes, bytes > 0 else { return .near }

    let perFile: Double
    switch shape {
    case .movie, .episode:
        perFile = Double(bytes)
    case .seasonPack(let episodes):
        // A pack is big by definition. Judge it per episode when we know the count; without one
        // there is nothing meaningful to compare, so leave it unpenalised rather than ranking
        // every season pack in existence last.
        guard let episodes, episodes > 0 else { return .ideal }
        perFile = Double(bytes) / Double(episodes)
    }

    let band = idealBand(resolution: resolution, shape: shape)
    if perFile >= band.lower && perFile <= band.upper { return .ideal }
    // Asymmetric tolerance. Undersize is halved — a file well under the band is usually a
    // mislabelled or upscaled release. Oversize is 1.5×, tight enough that the 70–80 GB releases
    // this exists to demote land in `.far` rather than scraping into `.near`.
    if perFile >= band.lower / 2 && perFile <= band.upper * 1.5 { return .near }
    return .far
}

/// Which side of its ideal band a file falls on.
///
/// `SizeFit` deliberately collapses both directions into `.far` — for RANKING that is right, since
/// a bloated file and a mislabelled tiny one should both lose. But a version list needs to tell
/// them apart: the big ones get a section of their own so they stay visible instead of sitting at
/// the bottom of thirty rows, while an undersized release belongs with the ordinary ones.
public enum SizeClass: Sendable, Equatable {
    /// Below the band — usually a mislabelled or upscaled release.
    case under
    /// Inside the band, close enough to it, or not judgeable.
    case fits
    /// Above the band: the 70–80GB REMUXes that open slowly and skip roughly.
    case over
}

/// Which side of its ideal band this file falls on. Anything that cannot be judged — an unknown
/// size, a season pack with no episode count — is `.fits`, never `.over`: calling a release
/// oversized on no evidence would hide an ordinary one away in the big-files section.
public func sizeClass(bytes: Int?, resolution: String?, shape: ReleaseShape) -> SizeClass {
    guard let bytes, bytes > 0 else { return .fits }

    let perFile: Double
    switch shape {
    case .movie, .episode:
        perFile = Double(bytes)
    case .seasonPack(let episodes):
        guard let episodes, episodes > 0 else { return .fits }
        perFile = Double(bytes) / Double(episodes)
    }

    let band = idealBand(resolution: resolution, shape: shape)
    if perFile > band.upper { return .over }
    if perFile < band.lower { return .under }
    return .fits
}

/// The size one playable file should reasonably weigh, in bytes. Decimal GB throughout, matching
/// how torrent indexers advertise sizes (see `TorrentioStreamSource.parseSize`).
private func idealBand(resolution: String?, shape: ReleaseShape) -> (lower: Double, upper: Double) {
    let gb = 1_000_000_000.0
    // An episode is a fraction of a film's runtime, so it gets its own bands rather than a
    // scaled-down film's — the ratio between them is not constant across resolutions.
    let isEpisode: Bool
    switch shape {
    case .movie: isEpisode = false
    case .episode, .seasonPack: isEpisode = true
    }

    switch (resolution, isEpisode) {                 // ParsedRelease stores resolution lowercased
    case ("2160p", false): return (12 * gb, 35 * gb)
    case ("1080p", false): return (4 * gb, 18 * gb)
    case ("720p", false): return (1.5 * gb, 8 * gb)
    case ("480p", false): return (0.7 * gb, 3 * gb)
    case (_, false): return (3 * gb, 25 * gb)        // unknown resolution: a wide, forgiving band

    case ("2160p", true): return (2 * gb, 9 * gb)
    case ("1080p", true): return (0.8 * gb, 5 * gb)
    case ("720p", true): return (0.3 * gb, 2.5 * gb)
    case ("480p", true): return (0.15 * gb, 1.2 * gb)
    case (_, true): return (0.5 * gb, 7 * gb)
    }
}
