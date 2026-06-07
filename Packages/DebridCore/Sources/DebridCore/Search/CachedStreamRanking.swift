/// Ranking for cached search results: clean original-language audio first, then quality, size.
public extension CachedStream {
    /// Whether this stream's audio includes `language` (nil language → false).
    func includes(language: String?) -> Bool {
        guard let language else { return false }
        return languages.contains(language)
    }

    /// Whether the title tags an audio language OTHER than the original — i.e. a foreign dub /
    /// multi-audio release (e.g. "Ger.Eng.Dubbed", "ITA.ENG"). Crucially, an UNTAGGED release
    /// (no detected languages) is NOT foreign: clean English rips usually carry no language tag,
    /// so absence of a tag must not be mistaken for a non-original dub. nil original → never foreign.
    func hasForeignAudio(relativeTo original: String?) -> Bool {
        guard let original else { return false }
        return languages.contains { $0 != original }
    }
}

public extension Array where Element == CachedStream {
    /// Best-first. **Clean original-language audio dominates** (releases with no foreign-language
    /// tag rank above foreign dubs), then an explicit original-language tag, then quality, size,
    /// and infoHash (deterministic tiebreak). When `originalLanguage` is nil, ranks by quality/size.
    func rankedFor(originalLanguage: String?) -> [CachedStream] {
        sorted { a, b in
            let af = a.hasForeignAudio(relativeTo: originalLanguage)
            let bf = b.hasForeignAudio(relativeTo: originalLanguage)
            if af != bf { return !af && bf }                 // clean / untagged before foreign dubs
            let ao = a.includes(language: originalLanguage)
            let bo = b.includes(language: originalLanguage)
            if ao != bo { return ao && !bo }                 // explicit original tag before untagged
            if a.qualityRank != b.qualityRank { return a.qualityRank > b.qualityRank }
            let asz = a.sizeBytes ?? 0, bsz = b.sizeBytes ?? 0
            if asz != bsz { return asz > bsz }
            return a.infoHash < b.infoHash
        }
    }

    /// The top pick plus whether it's a genuine language fallback — a foreign-dub release that
    /// lacks the original language entirely. An untagged release is NOT flagged (most likely the
    /// original). `isFallback` is false when `originalLanguage` is nil.
    func bestMatch(originalLanguage: String?) -> (stream: CachedStream, isFallback: Bool)? {
        guard let best = rankedFor(originalLanguage: originalLanguage).first else { return nil }
        let isFallback = best.hasForeignAudio(relativeTo: originalLanguage)
            && !best.includes(language: originalLanguage)
        return (best, isFallback)
    }
}
