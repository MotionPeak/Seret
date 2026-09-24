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
    /// How well this stream's size fits its resolution and shape — see `sizeFit`. A season pack
    /// is judged per episode when the count is known, and left unpenalised when it is not.
    func fit(episodesInSeason: Int?) -> SizeFit {
        sizeFit(bytes: sizeBytes, resolution: parsed.resolution,
                shape: ReleaseShape.of(parsed, episodes: episodesInSeason))
    }

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
    /// `originalLanguage` is nil, ranks by quality/size only. With `subtitles`, a version with
    /// Hebrew subtitles ranks above every other (see `hebrewBoostTier` for the guards).
    func rankedFor(originalLanguage: String?, episodesInSeason: Int? = nil,
                   subtitles: SubtitleEvidenceSet = .empty) -> [CachedStream] {
        sorted { a, b in
            let at = a.audioTier(relativeTo: originalLanguage)
            let bt = b.audioTier(relativeTo: originalLanguage)
            if at != bt { return at < bt }
            // Below language, but above resolution: `qualityRank`'s unplayable-audio penalty is
            // sized to lose "regardless of resolution", and it cannot do that from below the
            // resolution comparison — it would only ever be consulted between two releases of the
            // same resolution. Without this, "Get best" adds a 2160p TrueHD release that plays
            // silently in preference to a 1080p one that works.
            let aMute = isUnplayableAudio(a.parsed.audioCodec)
            let bMute = isUnplayableAudio(b.parsed.audioCodec)
            if aMute != bMute { return bMute }
            // Hebrew subtitles, above resolution: the owner's "always on top". A Hebrew version
            // outranks every other, a 720p one included. Below the two terms above, so it never
            // lifts a dub over the original or a silent file over one that plays; the rest of the
            // guards live in `hebrewBoostTier`.
            let ah = hebrewBoostTier(subtitles[version: a.infoHash], parsed: a.parsed,
                                     originalLanguage: originalLanguage)
            let bh = hebrewBoostTier(subtitles[version: b.infoHash], parsed: b.parsed,
                                     originalLanguage: originalLanguage)
            if ah != bh { return ah < bh }
            let ar = resolutionTier(a.parsed.resolution), br = resolutionTier(b.parsed.resolution)
            if ar != br { return ar > br }
            let af = a.fit(episodesInSeason: episodesInSeason)
            let bf = b.fit(episodesInSeason: episodesInSeason)
            if af != bf { return af > bf }
            if a.qualityRank != b.qualityRank { return a.qualityRank > b.qualityRank }
            // Within one fit band, bigger means a higher bitrate at the same size class.
            let asz = a.sizeBytes ?? 0, bsz = b.sizeBytes ?? 0
            if asz != bsz { return asz > bsz }
            return a.infoHash < b.infoHash
        }
    }

    /// The top pick plus whether it's a genuine language fallback — a foreign release with no
    /// original-language audio (tier 2). A clean or dual-audio pick is not flagged. `isFallback`
    /// is false when `originalLanguage` is nil.
    func bestMatch(originalLanguage: String?,
                   subtitles: SubtitleEvidenceSet = .empty) -> (stream: CachedStream, isFallback: Bool)? {
        guard let best = rankedFor(originalLanguage: originalLanguage, subtitles: subtitles).first else { return nil }
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
    func bestSeasonPack(forSeason season: Int, originalLanguage: String?,
                        subtitles: SubtitleEvidenceSet = .empty) -> (stream: CachedStream, isFallback: Bool)? {
        seasonPacks(forSeason: season).bestMatch(originalLanguage: originalLanguage, subtitles: subtitles)
    }
}
