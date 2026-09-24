/// The Hebrew-subtitle term the version rankers compare, lower first.
///
/// It is the evidence level, unless a guard says this version must not jump the queue. Then it
/// ranks exactly where it would have before Hebrew mattered:
/// - a film whose own language is Hebrew needs no subtitles to be understood;
/// - a theatre recording or screener is where a new release gets Hebrew subtitles first;
/// - a dub that has lost the film's own language is not what a subtitle reader is after.
///
/// A file that plays silently is kept down by the playable-audio term above this one.
func hebrewBoostTier(_ evidence: SubtitleEvidence?, parsed: ParsedRelease,
                     originalLanguage: String?) -> Int {
    let unboosted = HebrewSubtitles.none.rawValue
    guard let evidence, evidence.hebrew != .none else { return unboosted }
    let original = LanguageCode.normalize(originalLanguage)
    if original == "he" { return unboosted }
    if evidence.isTheatreCopy || isTheatreSource(parsed.source) { return unboosted }
    if let original, let audio = evidence.audioLanguages, !audio.contains(original) { return unboosted }
    return evidence.hebrew.rawValue
}
