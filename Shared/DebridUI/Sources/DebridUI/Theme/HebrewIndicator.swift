import DebridCore

/// The Hebrew mark a version row or a title's hero draws, the same in every app.
///
/// Two marks, because they promise different things. A Hebrew track INSIDE the file (or burned
/// into the picture, which a HebSubs release name usually means) is timed to that exact cut, so it
/// is always in sync: it gets its own mark, on a line of its own at the top of the row. A subtitle
/// OpenSubtitles made for the release usually fits but is a separate file that can drift, so it
/// keeps the gold pill beside the quality chips.
///
/// DebridCore's `badgeText` and `HebrewTitleChip.text` stay as they were: the web still reads them.
public enum HebrewIndicator: Sendable, Equatable {
    /// A Hebrew track in the file: the top-of-row mark.
    case inFile
    /// OpenSubtitles has a Hebrew subtitle made for this release: the pill.
    case matched
    /// The title's hero only: Hebrew exists for the film, but not made for Play's version.
    case available

    /// A version's mark; nil when nothing is known about its Hebrew.
    public init?(_ level: HebrewSubtitles) {
        switch level {
        case .builtIn, .builtInImage: self = .inFile
        case .matched: self = .matched
        case .none: return nil
        }
    }

    /// The hero's mark, drawn exactly as the rows draw it.
    public init(chip: HebrewTitleChip) {
        switch chip {
        case .builtIn: self = .inFile
        case .matched: self = .matched
        case .available: self = .available
        }
    }

    public var title: String {
        switch self {
        case .inFile: "Hebrew in the file"
        case .matched: "Hebrew · Matched"
        case .available: "Hebrew · Available"
        }
    }

    /// The promise only a track inside the file can make.
    public var detail: String? {
        self == .inFile ? "Always in sync" : nil
    }

    public var systemImage: String {
        self == .inFile ? "checkmark.seal.fill" : "captions.bubble.fill"
    }
}
