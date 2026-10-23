/// The order Play takes a title's own versions in, which is also the Versions list's order.
/// Pure and deterministic; the rules live in `PlayOrder.swift`.
public extension MediaSource {
    /// Higher is better. Resolution dominates, then source tier, then video codec.
    var qualityRank: Int { releaseQualityRank(for: parsed) }

    /// How well this file's size fits its resolution and shape — see `sizeFit`.
    var fit: SizeFit { sizeFit(bytes: sizeBytes, resolution: parsed.resolution,
                               shape: ReleaseShape.of(parsed)) }
}

public extension Array where Element == MediaSource {
    /// Sources in the order Play takes them — see `PlayPolicy` for the owner's rules and
    /// `PlayOrderKey` for the comparison. Deterministic: ties break by torrentID, then fileID.
    ///
    /// The film's language comes from `subtitles.originalLanguage`.
    ///
    /// The audio test is the first comparison, not a term inside `qualityRank`: a 2160p TrueHD
    /// version once won on resolution and played with no sound.
    func bestFirst(subtitles: SubtitleEvidenceSet = .empty) -> [MediaSource] {
        let policy = PlayPolicy(originalLanguage: subtitles.originalLanguage)
        let keyed = map { source -> (MediaSource, PlayOrderKey) in
            let evidence = subtitles[version: WatchKey.source(source)]
            let shape = ReleaseShape.of(source.parsed)
            return (source, PlayOrderKey(
                audioTier: 0,
                mute: isUnplayableAudio(source.parsed.audioCodec),
                suspect: isSuspectPicture(source.parsed, bytes: source.sizeBytes, shape: shape,
                                          theatreCopy: evidence?.isTheatreCopy ?? false),
                hebrew: policy.hebrewTier(evidence, parsed: source.parsed,
                                          originalLanguage: subtitles.originalLanguage),
                resolution: resolutionTier(source.parsed.resolution),
                weight: bytesPerFile(source.sizeBytes, shape: shape),
                quality: source.qualityRank))
        }
        return keyed.sorted { a, b in
            if let order = a.1.precedes(b.1) { return order }
            if a.0.torrentID != b.0.torrentID { return a.0.torrentID < b.0.torrentID }
            return (a.0.fileID ?? -1) < (b.0.fileID ?? -1)   // nil fileID (non-pack torrent) sorts before any real fileID
        }.map(\.0)
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
    ///
    /// The ranker's pick includes Hebrew subtitles when evidence is passed.
    func preferred(_ sourceKey: String?, subtitles: SubtitleEvidenceSet = .empty) -> MediaSource? {
        if let sourceKey, let chosen = first(where: { WatchKey.source($0) == sourceKey }) { return chosen }
        return bestFirst(subtitles: subtitles).first
    }
}
