/// Quality ranking for picking the default ("best") source and ordering the Versions list.
/// Pure and deterministic; the tier formula lives in the shared free function `qualityRank(for:)`.
public extension MediaSource {
    /// Higher is better. Resolution dominates, then source tier, then video codec.
    var qualityRank: Int { releaseQualityRank(for: parsed) }
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
