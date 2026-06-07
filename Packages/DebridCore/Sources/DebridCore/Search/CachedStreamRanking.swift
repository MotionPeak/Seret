/// Ranking for cached search results: original-language audio tier first, then quality, size.
public extension CachedStream {
    /// Whether this stream's audio includes `language` (nil language → false).
    func includes(language: String?) -> Bool {
        guard let language else { return false }
        return languages.contains(language)
    }

    /// Whether the release name is in a non-Latin script (Cyrillic / CJK / Arabic / Hebrew /
    /// Greek …). A name like "Сплит.2016.Remux" carries no ISO language tag yet is clearly a
    /// foreign (Russian) release — so an untagged *non-Latin* title must NOT be treated as the
    /// original-language version. (Accented Latin stays ≤ U+024F and is fine.)
    var hasNonLatinTitle: Bool {
        rawTitle.unicodeScalars.contains { $0.properties.isAlphabetic && $0.value > 0x024F }
    }

    /// Audio desirability for `original` — lower is better:
    /// 0 = clean original (explicit original-only tag, or untagged Latin-script → assume original),
    /// 1 = dual-audio that *includes* the original alongside a foreign track (a dub/multi release),
    /// 2 = foreign — no original track at all, or a non-Latin (foreign-script) untagged release.
    /// Returns 0 for every stream when `original` is nil (no preference).
    func audioTier(relativeTo original: String?) -> Int {
        guard let original else { return 0 }
        let hasOriginal = languages.contains(original)
        let hasForeign = languages.contains { $0 != original }
        if hasOriginal && !hasForeign { return 0 }
        if languages.isEmpty && !hasNonLatinTitle { return 0 }   // untagged Latin → assume original
        if hasOriginal && hasForeign { return 1 }                // dual audio: has original + a dub
        return 2                                                  // foreign-only / foreign-script
    }
}

public extension Array where Element == CachedStream {
    /// Best-first. **Audio tier dominates** (clean original → dual-audio dub → foreign), then
    /// quality, then size, then infoHash (deterministic tiebreak). Quality decides *within* a
    /// tier, so a 2160p REMUX never loses to a 720p rip that merely shares the tier. When
    /// `originalLanguage` is nil, ranks by quality/size only.
    func rankedFor(originalLanguage: String?) -> [CachedStream] {
        sorted { a, b in
            let at = a.audioTier(relativeTo: originalLanguage)
            let bt = b.audioTier(relativeTo: originalLanguage)
            if at != bt { return at < bt }
            if a.qualityRank != b.qualityRank { return a.qualityRank > b.qualityRank }
            let asz = a.sizeBytes ?? 0, bsz = b.sizeBytes ?? 0
            if asz != bsz { return asz > bsz }
            return a.infoHash < b.infoHash
        }
    }

    /// The top pick plus whether it's a genuine language fallback — a foreign release with no
    /// original-language audio (tier 2). A clean or dual-audio pick is not flagged. `isFallback`
    /// is false when `originalLanguage` is nil.
    func bestMatch(originalLanguage: String?) -> (stream: CachedStream, isFallback: Bool)? {
        guard let best = rankedFor(originalLanguage: originalLanguage).first else { return nil }
        return (best, best.audioTier(relativeTo: originalLanguage) == 2)
    }

    /// The full-season packs in this list for `season`: releases that name the season but no
    /// single episode (`episode == nil`) and whose parsed season matches. Complete-series packs
    /// (no parsed season) are excluded — adding one would pull every season, not just this one.
    func seasonPacks(forSeason season: Int) -> [CachedStream] {
        filter { $0.parsed.episode == nil && $0.parsed.season == season }
    }

    /// The best cached full-season pack for `season` (audio tier + quality, same ranking as
    /// `bestMatch`), plus whether it's a language fallback. nil when no full-season pack is cached
    /// — the whole season can't be grabbed in a single torrent then.
    func bestSeasonPack(forSeason season: Int, originalLanguage: String?) -> (stream: CachedStream, isFallback: Bool)? {
        seasonPacks(forSeason: season).bestMatch(originalLanguage: originalLanguage)
    }
}
