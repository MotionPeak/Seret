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
    /// In the order Play takes them: original-language audio first (clean original → dual-audio
    /// dub → foreign), then the rules every version list follows — see `PlayPolicy` and
    /// `PlayOrderKey`. A season pack is weighed per episode when `episodesInSeason` is known.
    /// Ties break by infoHash.
    func rankedFor(originalLanguage: String?, episodesInSeason: Int? = nil,
                   subtitles: SubtitleEvidenceSet = .empty) -> [CachedStream] {
        let policy = PlayPolicy(originalLanguage: originalLanguage)
        let keyed = map { stream -> (CachedStream, PlayOrderKey) in
            let shape = ReleaseShape.of(stream.parsed, episodes: episodesInSeason)
            return (stream, PlayOrderKey(
                audioTier: stream.audioTier(relativeTo: originalLanguage),
                mute: isUnplayableAudio(stream.parsed.audioCodec),
                suspect: isSuspectPicture(stream.parsed, bytes: stream.sizeBytes, shape: shape,
                                          theatreCopy: stream.isTheatreCopy),
                hebrew: policy.hebrewTier(subtitles[version: stream.infoHash], parsed: stream.parsed,
                                          originalLanguage: originalLanguage),
                resolution: resolutionTier(stream.parsed.resolution),
                weight: bytesPerFile(stream.sizeBytes, shape: shape),
                quality: stream.qualityRank))
        }
        return keyed.sorted { a, b in
            a.1.precedes(b.1) ?? (a.0.infoHash < b.0.infoHash)
        }.map(\.0)
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
