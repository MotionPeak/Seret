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

    public static func rank(_ results: [SubtitleResult], against fileName: String,
                            videoFPS: Double?) -> [Ranked] {
        let target = tokens(of: fileName)
        let targetGroup = releaseGroup(of: fileName)
        let maxDownloads = Double(results.compactMap(\.downloadCount).max() ?? 0)

        let ranked = results.map { result -> Ranked in
            var score = 0.0
            var reasons: [Reason] = []

            if result.moviehashMatch == true {
                score += 1000
                reasons.append(.hashMatch)
            }

            let candidate = tokens(of: result.release ?? result.fileName ?? "")
            if let group = releaseGroup(of: result.release ?? result.fileName ?? ""),
               let targetGroup, group == targetGroup {
                score += 120
                reasons.append(.sameGroup)
            }
            if let r = target.intersection(resolutions).first, candidate.contains(r) {
                score += 40
                reasons.append(.sameResolution)
            }
            if let s = target.intersection(sources).first, candidate.contains(s) {
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
        let cleaned = name.lowercased()
            .replacingOccurrences(of: #"\.(srt|ass|ssa|sub|vtt|mkv|mp4|avi)$"#,
                                  with: "", options: .regularExpression)
        return Set(cleaned.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count > 1 })
    }

    /// The release group — conventionally the token after the final hyphen.
    private static func releaseGroup(of name: String) -> String? {
        let base = name.lowercased()
            .replacingOccurrences(of: #"\.(srt|ass|ssa|sub|vtt|mkv|mp4|avi)$"#,
                                  with: "", options: .regularExpression)
        guard let dash = base.lastIndex(of: "-") else { return nil }
        let group = base[base.index(after: dash)...]
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .first
            .map(String.init)
        guard let group, group.count >= 2 else { return nil }
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
