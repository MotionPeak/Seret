/// Ranking for cached search results: original-language audio first, then quality, then size.
public extension CachedStream {
    /// Whether this stream's audio includes `language` (nil language → false).
    func includes(language: String?) -> Bool {
        guard let language else { return false }
        return languages.contains(language)
    }
}

public extension Array where Element == CachedStream {
    /// Best-first. Original-language audio dominates, then quality, then size, then infoHash
    /// (deterministic tiebreak). When `originalLanguage` is nil, ranks by quality/size only.
    func rankedFor(originalLanguage: String?) -> [CachedStream] {
        sorted { a, b in
            let ao = a.includes(language: originalLanguage)
            let bo = b.includes(language: originalLanguage)
            if ao != bo { return ao && !bo }
            if a.qualityRank != b.qualityRank { return a.qualityRank > b.qualityRank }
            let asz = a.sizeBytes ?? 0, bsz = b.sizeBytes ?? 0
            if asz != bsz { return asz > bsz }
            return a.infoHash < b.infoHash
        }
    }

    /// The top pick plus whether it's a language fallback (lacks the original language).
    /// `isFallback` is false when `originalLanguage` is nil (no preference to miss).
    func bestMatch(originalLanguage: String?) -> (stream: CachedStream, isFallback: Bool)? {
        guard let best = rankedFor(originalLanguage: originalLanguage).first else { return nil }
        let isFallback = (originalLanguage != nil) && !best.includes(language: originalLanguage)
        return (best, isFallback)
    }
}
