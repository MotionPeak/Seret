import Foundation

/// How a version stands on Hebrew subtitles, best first. The order IS the ranking.
public enum HebrewSubtitles: Int, Sendable, Codable, Comparable, CaseIterable {
    /// A Hebrew text track inside the file, or a release name that says it has one.
    case builtIn = 0
    /// Only picture (PGS / VobSub) Hebrew tracks inside the file: in sync, but not restylable.
    case builtInImage = 1
    /// OpenSubtitles has a Hebrew subtitle made for this release (`SubtitleMatch` "good" or better).
    case matched = 2
    case none = 3

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Both in-file kinds read the same to the viewer: "Built in".
    public var isBuiltIn: Bool { self == .builtIn || self == .builtInImage }

    /// A version row's badge, nil when there is nothing to say.
    public var badgeText: String? {
        switch self {
        case .builtIn, .builtInImage: "Hebrew · Built in"
        case .matched: "Hebrew · Matched"
        case .none: nil
        }
    }
}

/// What the rankers know about one version's subtitles.
public struct SubtitleEvidence: Sendable, Equatable {
    public var hebrew: HebrewSubtitles
    /// Audio languages the version is known to carry (ISO 639-1); nil when nothing says.
    public var audioLanguages: [String]?

    public init(hebrew: HebrewSubtitles, audioLanguages: [String]? = nil) {
        self.hebrew = hebrew
        self.audioLanguages = audioLanguages
    }
}

/// The title page's Hebrew chip: about the version Play will use when there is one, about the film
/// otherwise. One definition, shared by both apps and the web.
public enum HebrewTitleChip: String, Sendable, Equatable {
    case builtIn, matched, available

    /// nil hides the chip — nothing found, or not checked yet.
    public static func forTitle(playing source: MediaSource?, subtitles: SubtitleEvidenceSet,
                                hebrewResults: [SubtitleResult]?) -> HebrewTitleChip? {
        if let source {
            let level = subtitles.hebrew(forVersion: WatchKey.source(source))
            if level.isBuiltIn { return .builtIn }
            if level == .matched { return .matched }
        }
        return hebrewResults?.isEmpty == false ? .available : nil
    }

    public var text: String {
        switch self {
        case .builtIn: "Hebrew · Built in"
        case .matched: "Hebrew · Matched"
        case .available: "Hebrew · Available"
        }
    }
}
