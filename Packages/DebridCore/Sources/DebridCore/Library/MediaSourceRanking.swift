/// Quality ranking for picking the default ("best") source and ordering the Versions list.
/// Pure and deterministic; the tier formula lives in the shared free function `qualityRank(for:)`.
public extension MediaSource {
    /// Higher is better. Resolution dominates, then source tier, then video codec.
    var qualityRank: Int { releaseQualityRank(for: parsed) }

    /// How well this file's size fits its resolution and shape — see `sizeFit`.
    var fit: SizeFit { sizeFit(bytes: sizeBytes, resolution: parsed.resolution,
                               shape: ReleaseShape.of(parsed)) }
}

public extension Array where Element == MediaSource {
    /// Sources best-first. Deterministic: ties break by torrentID, then fileID.
    ///
    /// Playable audio outranks everything, then resolution, then size fit, then source tier. That
    /// middle placement of size is the whole point: `REMUX` is the top source tier and 60–90 GB by
    /// construction, so a size term that merely broke ties would never be reached — the bloat would
    /// already have won.
    ///
    /// The audio test has to be its own first comparison, not a term inside `qualityRank`. The
    /// penalty there is deliberately larger than any positive rank so a release that will play
    /// silently loses "regardless of resolution" — but once resolution became the first comparison,
    /// `qualityRank` was only ever consulted between two releases of the SAME resolution, and the
    /// penalty stopped applying across resolutions entirely. A 2160p TrueHD version won by default
    /// and played with no sound.
    func bestFirst() -> [MediaSource] {
        sorted { a, b in
            let aMute = isUnplayableAudio(a.parsed.audioCodec)
            let bMute = isUnplayableAudio(b.parsed.audioCodec)
            if aMute != bMute { return bMute }
            let ar = resolutionTier(a.parsed.resolution), br = resolutionTier(b.parsed.resolution)
            if ar != br { return ar > br }
            if a.fit != b.fit { return a.fit > b.fit }
            if a.qualityRank != b.qualityRank { return a.qualityRank > b.qualityRank }
            // Within one fit band, bigger means a higher bitrate at the same size class.
            let asz = a.sizeBytes ?? 0, bsz = b.sizeBytes ?? 0
            if asz != bsz { return asz > bsz }
            if a.torrentID != b.torrentID { return a.torrentID < b.torrentID }
            return (a.fileID ?? -1) < (b.fileID ?? -1)   // nil fileID (non-pack torrent) sorts before any real fileID
        }
    }

    /// The single best source, or nil when empty.
    var best: MediaSource? { bestFirst().first }

    /// **The version playback will actually use**: the viewer's chosen one when it still resolves,
    /// otherwise the quality ranker.
    ///
    /// One definition, because more than one screen starts playback — the title page's Play button
    /// and Home's Continue Watching — and they disagreed: Home resolved with `best` and never asked
    /// for the preference, so a version chosen on the title page was silently ignored by the very
    /// screen the viewer resumes from.
    ///
    /// The fallback is load-bearing: a preference pointing at a torrent since deleted from RD must
    /// degrade to the ranker rather than leave Play permanently broken.
    func preferred(_ sourceKey: String?) -> MediaSource? {
        if let sourceKey, let chosen = first(where: { WatchKey.source($0) == sourceKey }) { return chosen }
        return best
    }
}
