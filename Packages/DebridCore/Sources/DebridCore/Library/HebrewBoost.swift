/// The Hebrew-subtitle term the version rankers compare, lower first.
///
/// It is the evidence level, unless a guard says this version must not jump the queue. Then it
/// ranks exactly where it would have before Hebrew mattered:
/// - the film's language is unknown, so the guards below cannot be applied (TMDB failed, or only
///   the player has reported on this title) — the badges still show, nothing jumps;
/// - a film whose own language is Hebrew needs no subtitles to be understood;
/// - a theatre recording or screener is where a new release gets Hebrew subtitles first;
/// - a dub that has lost the film's own language is not what a subtitle reader is after.
///
/// A file that plays silently is kept down by the playable-audio term above this one.
func hebrewBoostTier(_ evidence: SubtitleEvidence?, parsed: ParsedRelease,
                     originalLanguage: String?) -> Int {
    let unboosted = HebrewSubtitles.none.rawValue
    guard let evidence, evidence.hebrew != .none else { return unboosted }
    guard let original = LanguageCode.normalize(originalLanguage), original != "he" else { return unboosted }
    // TV is never recorded in a cinema — and the parser, which matches a source anywhere in a
    // name, reads a show called "Cam Girl" as a CAM copy.
    if evidence.isTheatreCopy || (!parsed.isTV && isTheatreSource(parsed.source)) { return unboosted }
    if let audio = evidence.audioLanguages,
       !audio.contains(where: { LanguageCode.sameLanguage($0, original) }) { return unboosted }
    return evidence.hebrew.rawValue
}
