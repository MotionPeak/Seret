import Foundation

/// Turns a release filename into a `ParsedRelease`. Pure and dependency-free.
/// Metadata fields are matched by regex on the original (dotted) name; the title is
/// the run of leading tokens before the first metadata token.
public struct FilenameParser: Sendable {
    public init() {}

    public func parse(_ raw: String) -> ParsedRelease {
        let name = String(raw.split(separator: "/").last ?? Substring(raw))
        let stem = Self.stripExtension(name)

        let releaseGroup = Self.extractReleaseGroup(stem)
        let resolution = Self.match(stem, Self.reResolution)?.lowercased()
        let source = Self.detectSource(stem)
        let videoCodec = Self.normalizeVideo(Self.match(stem, Self.reVideo))
        let audioCodec = Self.normalizeAudio(Self.match(stem, Self.reAudio))
        let (title, year) = Self.titleAndYear(stem)

        var season: Int?
        var episode: Int?
        if let fansub = Self.fansubEpisode(stem) {
            // `[Group] Show - 07 [1080p]` carries its episode as a bare number after a hyphen, and
            // no S/E pattern at all. Reading the title but not the number left every episode of a
            // series parsed as a MOVIE named for the show — so the whole series collapsed into one
            // library entry. Absolute numbering is filed under season 1, which groups them as the
            // show they are — but a later season is stated as a bare `S2` token, and forcing season
            // 1 on that made a season-2 premiere collide with the season-1 one: both keyed `s1e1`,
            // so the show grew ONE episode row holding two files and whichever ranked higher is
            // what "S01E01" played.
            season = Self.captures(stem, Self.reSeasonBare).flatMap { Int($0[0]) } ?? 1
            episode = fansub
        } else if let g = Self.captures(stem, Self.reSeasonEpisode) {
            season = Int(g[0]); episode = Int(g[1])
        } else if let g = Self.captures(stem, Self.reNxM) {
            season = Int(g[0]); episode = Int(g[1])
        } else if let g = Self.captures(stem, Self.reSeasonWord) {
            season = Int(g[0])
        } else if let g = Self.captures(stem, Self.reSeasonBare) {
            season = Int(g[0])
        }

        return ParsedRelease(
            title: title,
            year: year, season: season, episode: episode,
            resolution: resolution, source: source, videoCodec: videoCodec,
            audioCodec: audioCodec, releaseGroup: releaseGroup)
    }

    // MARK: - Compiled patterns (compiled once — patterns are static literals, so try! is safe)

    /// The final hyphenated pair of a name, so a trailing compound tag ("WEB-DL") can be told
    /// apart from a real release group ("x264-NTb").
    private static let reTrailingHyphenPair = make(#"([A-Za-z0-9]+)-([A-Za-z0-9]{2,})$"#)
    /// A token that is nothing but a year, bare or wrapped: `2016`, `(2016)`, `[2016]`.
    private static let reYearToken = make(#"^[(\[]?((?:19|20)\d{2})[)\]]?$"#)
    private static let reResolution = make(#"(?i)\b(2160p|1080p|720p|480p)\b"#)
    private static let reSource = make(#"(?i)\b(blu-?ray|bd-?rip|web-?dl|web-?rip|hdtv|dvd-?rip|remux|hdrip|hd-?ts|hd-?cam|telesync|telecine|camrip|cam|screener)\b"#)
    private static let reRemux = make(#"(?i)\bremux\b"#)
    private static let reVideo = make(#"(?i)\b(x265|x264|h\.?265|h\.?264|hevc|avc)\b"#)
    private static let reAudio = make(#"(?i)\b(dts-?hd|truehd|atmos|ddp?5\.1|ddp|dts|eac3|ac3|aac|flac)\b"#)
    private static let reYear = make(#"\b(19\d{2}|20\d{2})\b"#)
    // The separator is optional because `S01.E01` / `S01 E01` / `S01_E01` are common in the wild.
    // Without it those parse as a season PACK with no episode, which had two downstream costs: a
    // pack is exempt from size ranking (there is nothing to compare one against), so a 40 GB single
    // episode dodged the size policy and outranked a right-sized release; and a pack whose FILES
    // are named that way had every episode skipped when the library expanded it. Digits after `E`
    // are still required, so `S01.Extras` remains a pack.
    // `\b` would not do here: `_` is a word character, so `Show_S01_E01` has no boundary before the
    // `S` or after the episode digits. Explicit non-alphanumeric lookarounds cover `_` too.
    // The trailing group makes a DOUBLE episode (`S01E01E02`, `S02E13-E14`) parse as an episode.
    // Without it `S01E01E02` matched nothing at all: the greedy `E(\d{1,3})` left an `E` in front
    // of the trailing-boundary lookaround, and backtracking could not rescue it, so the file fell
    // through to `reSeasonBare` — which also fails, because `\bS01\b` needs a boundary the `E`
    // does not provide. The result was a double episode parsed as a MOVIE named for the show, so
    // neither episode ever reached the library. The FIRST episode number is reported: the library
    // models one episode per file, and appearing as E01 beats not appearing.
    private static let reSeasonEpisode =
        make(#"(?i)(?<![A-Za-z0-9])S(\d{1,2})[._\s-]?E(\d{1,3})(?:[._\s-]?E?\d{1,3})?(?![A-Za-z0-9])"#)
    private static let reNxM = make(#"(?i)\b(\d{1,2})x(\d{1,3})\b"#)
    private static let reSeasonWord = make(#"(?i)\bseason\s?(\d{1,2})\b"#)
    private static let reSeasonBare = make(#"(?i)\bS(\d{1,2})\b"#)
    private static let reExtension = make(#"\.[A-Za-z0-9]{2,4}$"#)

    /// Token patterns that mark the end of the title (compiled once). Includes audio/HDR
    /// tokens so a name like `Some.Film.FLAC.1080p…` stops the title at `FLAC`.
    private static let metadataTokenRegexes: [NSRegularExpression] = [
        #"^(19|20)\d{2}$"#,
        #"^[(\[](19|20)\d{2}[)\]]$"#,   // a parenthesised/bracketed year: "(2016)" / "[2016]"
        #"(?i)^s\d{1,2}e\d{1,3}(?:[._\s-]?e?\d{1,3})?$"#,   // single or double episode
        #"(?i)^s\d{1,2}$"#,
        // A season RANGE — "S01-S04", "S1-S4", "S01-04". The token split does not break on `-`, so
        // this arrives whole and `^s\d{1,2}$` never matched it: the title ran on through the rest
        // of the name ("Sherlock S01-S04 + Extras Complete"), and since shows group by title key
        // the pack became a separate show TMDB could not match, with every episode stranded in it.
        // Anchored at both ends, so a genuinely hyphenated title like "Spider-Man" is untouched.
        #"(?i)^s\d{1,2}-s?\d{1,2}$"#,
        #"(?i)^\d{1,2}x\d{1,3}$"#,
        #"(?i)^(2160p|1080p|720p|480p)$"#,
        #"(?i)^season$"#,
        #"(?i)^(bluray|blu-ray|bdrip|web-?dl|web-?rip|hdtv|dvdrip|remux|hdrip|hd-?ts|hd-?cam|telesync|telecine|camrip|cam|screener|x265|x264|h264|h265|hevc|avc|amzn|uhd|hdr|hdr10|dv|dts|dts-?hd|truehd|atmos|ddp|eac3|ac3|aac|flac)$"#,
    ].map(make)

    private static func make(_ pattern: String) -> NSRegularExpression {
        // Patterns are compile-time string literals; a failure is a programmer error.
        try! NSRegularExpression(pattern: pattern)
    }

    // MARK: - Title

    /// Title and release year together, because they cannot be decided apart.
    ///
    /// A year-shaped token used to end the title AND become the release year, whichever one came
    /// first. That is wrong in both directions for a film whose title contains a year: "Blade
    /// Runner 2049 2017" yielded the title "Blade Runner" with year 2049, and "2012 2009" yielded
    /// no title tokens at all — so the empty-title fallback handed TMDB the entire raw release
    /// string. Either way enrichment matched nothing, and the title showed no poster.
    ///
    /// The rule: when a name carries several year-shaped tokens, only the LAST is the release year;
    /// earlier ones belong to the title. When it carries exactly one and nothing precedes it, that
    /// token IS the title (a film named for a year) and there is no release year to report.
    private static func titleAndYear(_ stem: String) -> (String, Int?) {
        let tokens = stem.split(whereSeparator: { $0 == "." || $0 == "_" || $0 == " " }).map(String.init)
        let yearIndices = tokens.indices.filter { yearValue(tokens[$0]) != nil }
        // A year-shaped token at the very START is always part of the title — nothing precedes it
        // for it to be the release year OF. Ending the title there truncated "2012 Doomsday" to
        // "2012", and since a movie is keyed by its title that collapsed it into the unrelated film
        // of that name.
        let releaseYearIndex = yearIndices.last { $0 != 0 }
        // Fansub-shaped: a leading bracketed tag AND a `- <episode>` marker. Both, because either
        // alone belongs to ordinary names too — `[REC] 2` opens with a bracket, and
        // `Mission.Impossible.-.2` ends in a hyphenated number.
        let isFansub = fansubEpisode(stem) != nil

        var titleTokens: [String] = []
        for (i, token) in tokens.enumerated() {
            if yearValue(token) != nil {
                if i == releaseYearIndex { break }
                titleTokens.append(token)      // an earlier year is part of the title
                continue
            }
            // A LEADING bracketed tag is the fansub group, not the title — `[SubsPlease] Show …`.
            // Only leading, and only when something else can serve as the title: a film actually
            // called `[REC]` must keep its name rather than fall back to the raw filename.
            if titleTokens.isEmpty, i == 0, Self.isBracketed(token),
               !isMetadataToken(Self.unbracketed(token)),
               Self.hasTitleAfterLeadingTag(tokens, hasEpisodeMarker: isFansub) {
                continue
            }
            // Fansub naming glues its tags to their brackets, so `[1080p]` never matched the
            // resolution stop-pattern and the whole filename became the title — which TMDB matches
            // nothing against, so the title showed no poster and no metadata at all.
            if isMetadataToken(Self.unbracketed(token)) { break }
            // A fully-bracketed token AFTER the title has begun is a tag, whatever it says —
            // `Some.Film.[TbZ]` is a release tag, not part of the film's name. Only after: the
            // leading one is handled above, where it may still BE the title.
            if !titleTokens.isEmpty, Self.isBracketed(token) { break }
            // `Show - 07`: a lone hyphen before a bare episode number is the fansub episode marker,
            // and the title ends there. Gated on the name actually BEING fansub-shaped (a leading
            // bracketed tag), because an ordinary release can legitimately end in a hyphenated
            // number — `Mission.Impossible.-.2.2000` is a sequel, not episode 2.
            if isFansub, token == "-", i + 1 < tokens.count, Self.isBareEpisodeNumber(tokens[i + 1]) {
                break
            }
            titleTokens.append(Self.unbracketed(token))
        }

        let joined = titleTokens.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        let year: Int?
        if let releaseYearIndex {
            year = yearValue(tokens[releaseYearIndex])
        } else if yearIndices.isEmpty {
            // Fall back to the stem-wide regex only when NO token is year-shaped: a name with no
            // separators ("Movie(2024)1080p") still has a findable year. When the one year-shaped
            // token is the title, that regex would hand the title straight back as the year.
            year = Self.match(stem, Self.reYear).flatMap { Int($0) }
        } else {
            year = nil
        }
        return (joined.isEmpty ? stem : joined, year)
    }

    /// Whether anything after a leading bracketed tag could serve as a title. When nothing can,
    /// the bracketed token IS the title — `[REC]` is a film.
    ///
    /// `hasEpisodeMarker` decides what a bare NUMBER means there. `[REC] 2` is a sequel, so the
    /// bracketed token has to stay or the title becomes the bare "2" — which TMDB will match to
    /// something, confidently and wrongly. But `[Group] 86 - 07` is a series called 86, and its
    /// `- <episode>` marker is what says so.
    private static func hasTitleAfterLeadingTag(_ tokens: [String], hasEpisodeMarker: Bool) -> Bool {
        for token in tokens.dropFirst() {
            if yearValue(token) != nil { return false }              // straight into the year
            if isMetadataToken(unbracketed(token)) { return false }   // straight into the metadata
            if token == "-" { continue }
            if isBareEpisodeNumber(token) { return hasEpisodeMarker }
            return true
        }
        return false
    }

    private static func isBracketed(_ token: String) -> Bool {
        (token.hasPrefix("[") && token.hasSuffix("]")) || (token.hasPrefix("(") && token.hasSuffix(")"))
    }

    /// The token with one layer of surrounding brackets removed, so `[1080p]` can be recognised as
    /// the resolution tag it is.
    private static func unbracketed(_ token: String) -> String {
        isBracketed(token) ? String(token.dropFirst().dropLast()) : token
    }

    /// `07` / `123` — the bare episode number fansub names put after a hyphen. Four digits would be
    /// a year, which is handled separately.
    /// The episode number in fansub naming — a bare number after a lone hyphen, in a name that
    /// begins with a bracketed group tag. Gated on that tag because an ordinary release can end in
    /// a hyphenated number that is part of its title.
    private static func fansubEpisode(_ stem: String) -> Int? {
        let tokens = stem.split(whereSeparator: { $0 == "." || $0 == "_" || $0 == " " }).map(String.init)
        guard isBracketed(tokens.first ?? "") else { return nil }
        for (i, token) in tokens.enumerated() where token == "-" {
            guard i + 1 < tokens.count, isBareEpisodeNumber(tokens[i + 1]) else { continue }
            return Int(tokens[i + 1])
        }
        return nil
    }

    private static func isBareEpisodeNumber(_ token: String) -> Bool {
        (1...3).contains(token.count) && token.allSatisfy(\.isNumber)
    }

    /// The year a token denotes, if it is nothing but a year — bare (`2016`) or wrapped (`(2016)`,
    /// `[2016]`).
    private static func yearValue(_ token: String) -> Int? {
        guard let digits = capture(token, reYearToken) else { return nil }
        return Int(digits)
    }

    /// The release group is whatever follows the final hyphen — but a name that simply ends in a
    /// compound source or audio tag has no group at all, and returning half the tag ("WEB-DL" →
    /// "DL", "DTS-HD" → "HD") poisoned the group match that ranks subtitles.
    private static func extractReleaseGroup(_ stem: String) -> String? {
        guard let pair = captures(stem, reTrailingHyphenPair), pair.count == 2 else { return nil }
        if isCompoundTag("\(pair[0])-\(pair[1])") { return nil }
        return pair[1]
    }

    /// True when a hyphenated pair is one token — a compound source or audio tag like `WEB-DL`,
    /// `Blu-Ray`, `DTS-HD` — rather than `<something>-<release group>`. Shared, because anything
    /// that reads "the bit after the last hyphen" as a release group makes the same mistake: it
    /// reads `WEB-DL` as the group `DL`, and then matches every other release that merely ends the
    /// same way.
    static func isCompoundTag(_ pair: String) -> Bool {
        matchesWholly(pair, reSource) || matchesWholly(pair, reAudio)
    }

    /// True when `re` matches the entire string, not merely a part of it.
    private static func matchesWholly(_ s: String, _ re: NSRegularExpression) -> Bool {
        let range = NSRange(s.startIndex..., in: s)
        guard let m = re.firstMatch(in: s, range: range) else { return false }
        return m.range == range
    }

    private static func isMetadataToken(_ t: String) -> Bool {
        let range = NSRange(t.startIndex..., in: t)
        return metadataTokenRegexes.contains { $0.firstMatch(in: t, range: range) != nil }
    }

    // MARK: - Normalization (canonical display forms)

    /// The source tier. REMUX is checked first: it's the top tier and co-occurs with BluRay/UHD in
    /// the name (e.g. "BluRay.REMUX"), but `reSource` matches left-to-right so "BluRay" would win and
    /// a true remux would mis-rank below a plain BluRay.
    private static func detectSource(_ stem: String) -> String? {
        if match(stem, reRemux) != nil { return "REMUX" }
        return normalizeSource(match(stem, reSource))
    }

    private static func normalizeSource(_ s: String?) -> String? {
        guard let s = s?.lowercased() else { return nil }
        if s.hasPrefix("blu") { return "BluRay" }
        if s.replacingOccurrences(of: "-", with: "") == "webdl" { return "WEB-DL" }
        if s.replacingOccurrences(of: "-", with: "") == "webrip" { return "WEBRip" }
        if s.contains("remux") { return "REMUX" }
        if s.contains("hdtv") { return "HDTV" }
        if s.contains("bd") { return "BDRip" }
        if s.contains("dvd") { return "DVDRip" }
        if s.contains("hdrip") { return "HDRip" }
        return s.uppercased()
    }

    private static func normalizeVideo(_ s: String?) -> String? {
        guard let s = s?.lowercased().replacingOccurrences(of: ".", with: "") else { return nil }
        switch s {
        case "x265": return "x265"
        case "x264": return "x264"
        case "hevc": return "HEVC"
        case "h265": return "h265"
        case "avc": return "AVC"
        case "h264": return "h264"
        default: return s
        }
    }

    private static func normalizeAudio(_ s: String?) -> String? {
        guard let raw = s else { return nil }
        let s = raw.lowercased()
        if s.replacingOccurrences(of: "-", with: "") == "dtshd" { return "DTS-HD" }
        if s.hasPrefix("dd") { return raw.uppercased() }   // DDP5.1 / DD5.1 / DDP — preserve the actual match, don't assume 5.1
        if s == "truehd" { return "TrueHD" }
        if s == "atmos" { return "Atmos" }
        if s == "eac3" { return "EAC3" }
        if s == "ac3" { return "AC3" }
        if s == "aac" { return "AAC" }
        if s == "flac" { return "FLAC" }
        if s == "dts" { return "DTS" }
        return raw.uppercased()
    }

    // MARK: - Regex helpers

    private static func stripExtension(_ s: String) -> String {
        let exts: Set<String> = ["mkv", "mp4", "avi", "m4v", "mov", "ts", "wmv", "srt", "ass"]
        let range = NSRange(s.startIndex..., in: s)
        guard let m = reExtension.firstMatch(in: s, range: range), let r = Range(m.range, in: s) else { return s }
        let ext = s[r].dropFirst().lowercased()
        return exts.contains(String(ext)) ? String(s[s.startIndex..<r.lowerBound]) : s
    }

    private static func match(_ s: String, _ re: NSRegularExpression) -> String? {
        let range = NSRange(s.startIndex..., in: s)
        guard let m = re.firstMatch(in: s, range: range), let r = Range(m.range, in: s) else { return nil }
        return String(s[r])
    }

    private static func capture(_ s: String, _ re: NSRegularExpression) -> String? {
        captures(s, re)?.first
    }

    private static func captures(_ s: String, _ re: NSRegularExpression) -> [String]? {
        let range = NSRange(s.startIndex..., in: s)
        guard let m = re.firstMatch(in: s, range: range), m.numberOfRanges > 1 else { return nil }
        var groups: [String] = []
        for i in 1..<m.numberOfRanges {
            guard let r = Range(m.range(at: i), in: s) else { return nil }
            groups.append(String(s[r]))
        }
        return groups
    }
}
