import Foundation

/// Evidence for one title's versions, plus the title's language: the whole input the Hebrew term
/// of a ranking needs.
public struct SubtitleEvidenceSet: Sendable, Equatable {
    /// Keyed by version: `WatchKey.source` for an owned copy, the info hash for a search result.
    public var byVersion: [String: SubtitleEvidence]
    /// The title's original language (ISO 639-1), when known.
    public var originalLanguage: String?

    public init(byVersion: [String: SubtitleEvidence] = [:], originalLanguage: String? = nil) {
        self.byVersion = byVersion
        self.originalLanguage = originalLanguage
    }

    public static let empty = SubtitleEvidenceSet()

    public subscript(version id: String) -> SubtitleEvidence? { byVersion[id] }

    /// The Hebrew level of one version; `.none` when nothing is known.
    public func hebrew(forVersion id: String) -> HebrewSubtitles { byVersion[id]?.hebrew ?? .none }

    /// `other` laid over this set, for evidence that arrives in pieces.
    public func merging(_ other: SubtitleEvidenceSet) -> SubtitleEvidenceSet {
        SubtitleEvidenceSet(byVersion: byVersion.merging(other.byVersion) { _, newer in newer },
                            originalLanguage: other.originalLanguage ?? originalLanguage)
    }
}

public extension SubtitleEvidenceSet {
    /// Search results: a Hebrew subtitle tag in the name is built in; a Hebrew subtitle
    /// OpenSubtitles made for the release is matched. Nothing is read from a file we do not own.
    static func candidates(_ streams: [CachedStream], hebrewResults: [SubtitleResult],
                           originalLanguage: String?) -> SubtitleEvidenceSet {
        var byVersion: [String: SubtitleEvidence] = [:]
        for stream in streams {
            let level: HebrewSubtitles
            if stream.subtitleLanguages.contains("he") {
                level = .builtIn
            } else if SubtitleMatch.hasMatch(in: hebrewResults, for: stream.rawTitle, videoFPS: nil) {
                level = .matched
            } else {
                level = .none
            }
            byVersion[stream.infoHash] = SubtitleEvidence(
                hebrew: level, audioLanguages: stream.languages.isEmpty ? nil : stream.languages)
        }
        return SubtitleEvidenceSet(byVersion: byVersion,
                                   originalLanguage: LanguageCode.normalize(originalLanguage))
    }

    /// Owned copies: what each file carries (from its header or from playback) and, failing that, a
    /// Hebrew subtitle made for its release. Matched against the same reconstructed name the player
    /// ranks downloads with, so "Matched" here is the subtitle the player would fetch.
    static func owned(_ sources: [MediaSource], records: [String: VersionSubtitleRecord],
                      hebrewResults: [SubtitleResult], originalLanguage: String?) -> SubtitleEvidenceSet {
        var byVersion: [String: SubtitleEvidence] = [:]
        for source in sources {
            let key = WatchKey.source(source)
            let record = records[key]
            var level = record?.hebrewLevel ?? .none
            if level == .none,
               SubtitleMatch.hasMatch(in: hebrewResults, for: source.releaseNameForMatching,
                                      videoFPS: record?.frameRate) {
                level = .matched
            }
            byVersion[key] = SubtitleEvidence(hebrew: level, audioLanguages: record?.audioLanguages)
        }
        return SubtitleEvidenceSet(byVersion: byVersion,
                                   originalLanguage: LanguageCode.normalize(originalLanguage))
    }
}
