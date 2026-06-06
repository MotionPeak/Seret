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
}
