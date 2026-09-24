import Foundation

/// Ranks subtitle search hits by how well each one actually matches the file being played.
///
/// Priority: an exact file-hash match (a sync guarantee) beats release-name agreement, which
/// beats frame-rate agreement, which beats popularity. Pure and `Double`-based so the ranking is
/// unit-tested without a network.
public enum SubtitleMatch {

    /// How confident we are that a subtitle is in sync, for the badge shown next to it.
    public enum Quality: Sendable, Equatable {
        /// Uploaded against this exact file. Perfect sync.
        case perfect
        /// Same release group or a strong release-name overlap.
        case good
        /// A different source. Usable, may need a timing nudge.
        case uncertain
    }

    /// Why a subtitle scored the way it did — surfaced in the UI so the ranking is legible.
    public enum Reason: Sendable, Equatable {
        case hashMatch
        case sameGroup
        case sameResolution
        case sameSource
        case fpsMatch
        case fpsMismatch
        case trusted
        case aiTranslated
    }

    public struct Ranked: Sendable, Equatable {
        public let result: SubtitleResult
        public let score: Double
        public let quality: Quality
        public let reasons: [Reason]
    }

    /// Tokens that carry real matching signal. Everything else in a release name is noise.
    private static let resolutions: Set<String> = ["480p", "576p", "720p", "1080p", "1440p", "2160p", "4k"]
    private static let sources: Set<String> = ["bluray", "blu-ray", "bdrip", "brrip", "web-dl", "webdl",
                                               "webrip", "web", "hdtv", "dvdrip", "remux", "uhd"]

    /// A search result with its release name broken down once. Matching one set of results
    /// against many releases — every version on a Versions screen — used to tokenise each result
    /// again for every version, on the main actor.
    public struct Prepared: Sendable {
        public let result: SubtitleResult
        let tokens: Set<String>
        let group: String?
    }

    public static func prepare(_ results: [SubtitleResult]) -> [Prepared] {
        results.map { result in
            let name = result.release ?? result.fileName ?? ""
            return Prepared(result: result, tokens: tokens(of: name), group: releaseGroup(of: name))
        }
    }

    public static func rank(_ results: [SubtitleResult], against fileName: String,
                            videoFPS: Double?) -> [Ranked] {
        rank(prepared: prepare(results), against: fileName, videoFPS: videoFPS)
    }

    public static func rank(prepared: [Prepared], against fileName: String,
                            videoFPS: Double?) -> [Ranked] {
        let target = tokens(of: fileName)
        let targetGroup = releaseGroup(of: fileName)
        let maxDownloads = Double(prepared.compactMap(\.result.downloadCount).max() ?? 0)

        let ranked = prepared.map { entry -> Ranked in
            let result = entry.result
            var score = 0.0
            var reasons: [Reason] = []

            if result.moviehashMatch == true {
                score += 1000
                reasons.append(.hashMatch)
            }

            let candidate = entry.tokens
            if let group = entry.group, let targetGroup, group == targetGroup {
                score += 120
                reasons.append(.sameGroup)
            }
            // Any shared token, never `.first` of a Set: a release named "BluRay.REMUX" holds two
            // source tokens, a Set's order changes from launch to launch, and the same file matched
            // a BluRay subtitle on one launch and not the next.
            if !target.intersection(resolutions).isDisjoint(with: candidate) {
                score += 40
                reasons.append(.sameResolution)
            }
            if !target.intersection(sources).isDisjoint(with: candidate) {
                score += 30
                reasons.append(.sameSource)
            }
            // General token overlap, on top of the specific signals above.
            score += Double(target.intersection(candidate).count) * 4

            if let videoFPS, let subFPS = result.fps, subFPS > 0 {
                if abs(subFPS - videoFPS) < 0.05 {
                    score += 50
                    reasons.append(.fpsMatch)
                } else {
                    score -= 60
                    reasons.append(.fpsMismatch)
                }
            }

            if result.trusted == true { score += 15; reasons.append(.trusted) }
            if result.aiTranslated == true { score -= 25; reasons.append(.aiTranslated) }

            // Popularity is the tiebreak only — normalised so it can never outweigh a real signal.
            if maxDownloads > 0, let downloads = result.downloadCount {
                score += (Double(downloads) / maxDownloads) * 10
            }

            return Ranked(result: result, score: score,
                          quality: quality(score: score, reasons: reasons), reasons: reasons)
        }

        return ranked.sorted { $0.score > $1.score }
    }

    private static func quality(score: Double, reasons: [Reason]) -> Quality {
        if reasons.contains(.hashMatch) { return .perfect }
        if reasons.contains(.sameGroup) || score >= 80 { return .good }
        return .uncertain
    }

    /// Lowercased, punctuation-split tokens; drops one-character noise.
    private static func tokens(of name: String) -> Set<String> {
        let cleaned = withoutExtension(name.lowercased())
        return Set(cleaned.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count > 1 })
    }

    /// Compiled once: a pattern passed to `replacingOccurrences` is compiled on every call.
    private static let fileExtension = try! NSRegularExpression(pattern: #"\.(srt|ass|ssa|sub|vtt|mkv|mp4|avi)$"#)

    private static func withoutExtension(_ name: String) -> String {
        fileExtension.stringByReplacingMatches(in: name, range: NSRange(name.startIndex..., in: name),
                                               withTemplate: "")
    }

    /// The release group — conventionally the token after the final hyphen.
    private static func releaseGroup(of name: String) -> String? {
        let base = withoutExtension(name.lowercased())
        guard let dash = base.lastIndex(of: "-") else { return nil }
        let group = base[base.index(after: dash)...]
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .first
            .map(String.init)
        guard let group, group.count >= 2 else { return nil }
        // `web-dl` and `dts-hd` are single tokens, not `<something>-<group>`. Reading the tail as a
        // group made every release ending in WEB-DL share the "group" DL, which scores as a release
        // match — so a subtitle from an unrelated release was ranked as if it came from this one.
        let preceding = base[..<dash].split(whereSeparator: { !$0.isLetter && !$0.isNumber }).last
        if let preceding, FilenameParser.isCompoundTag("\(preceding)-\(group)") { return nil }
        return group
    }
}

public extension MediaSource {
    /// A canonical release name for subtitle compatibility matching, rebuilt from the parsed
    /// fields. `ParsedRelease` keeps no original filename, and the reconstruction is better input
    /// than a raw path anyway: it is already normalised, and the release group is parsed rather
    /// than guessed.
    var releaseNameForMatching: String {
        var parts = [parsed.title.replacingOccurrences(of: " ", with: ".")]
        if let year = parsed.year { parts.append(String(year)) }
        if let season = parsed.season, let episode = parsed.episode {
            parts.append(String(format: "S%02dE%02d", season, episode))
        }
        parts += [parsed.resolution, parsed.source, parsed.videoCodec, parsed.audioCodec]
            .compactMap { $0 }
        let stem = parts.joined(separator: ".")
        guard let group = parsed.releaseGroup else { return stem }
        return "\(stem)-\(group)"
    }
}

public extension SubtitleMatch {
    /// Whether `results` holds a subtitle made for the release named `name`: a hash match, the same
    /// release group, or a strong name overlap. The bar the player's badge calls "good".
    static func hasMatch(in results: [SubtitleResult], for name: String, videoFPS: Double?) -> Bool {
        hasMatch(prepared: prepare(results), for: name, videoFPS: videoFPS)
    }

    static func hasMatch(prepared: [Prepared], for name: String, videoFPS: Double?) -> Bool {
        rank(prepared: prepared, against: name, videoFPS: videoFPS).contains { $0.quality != .uncertain }
    }
}
