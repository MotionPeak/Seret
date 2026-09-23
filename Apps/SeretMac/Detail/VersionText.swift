import DebridCore
import Foundation

/// Pure text/formatting for the Versions list and sheet — no view state, so every rule is testable
/// without mounting anything.
enum VersionText {
    /// Resolution, source, video codec, audio codec — non-nil, in that order. The same fields and
    /// order `TitleHero.qualityChips` already draws for the hero's own chip row.
    static func chips(_ p: ParsedRelease) -> [String] {
        [p.resolution, p.source, p.videoCodec, p.audioCodec].compactMap { $0 }
    }

    /// Finder-style size ("25 GB", "6.2 GB"), nil when the size is unknown.
    static func size(_ bytes: Int?) -> String? {
        guard let bytes, bytes > 0 else { return nil }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    /// "EN · HE", nil when there is nothing to show.
    static func languages(_ codes: [String]) -> String? {
        guard !codes.isEmpty else { return nil }
        return codes.map { $0.uppercased() }.joined(separator: " \u{00B7} ")
    }

    /// What an owned copy's row shows: its quality chips, its release group (nil when unparsed),
    /// and its size.
    static func ownedRow(_ s: MediaSource) -> (chips: [String], group: String?, size: String?) {
        (chips(s.parsed), s.parsed.releaseGroup, size(s.sizeBytes))
    }
}

/// One thing a Versions row's right-click menu can do.
enum VersionMenuItem: Hashable {
    case playThis, makeDefault, useBestAutomatically, remove

    var title: String {
        switch self {
        case .playThis: "Play This Version"
        case .makeDefault: "Make Default"
        case .useBestAutomatically: "Use Best Automatically"
        case .remove: "Remove This Version\u{2026}"
        }
    }

    var symbol: String {
        switch self {
        case .playThis: "play.fill"
        case .makeDefault: "checkmark.circle"
        case .useBestAutomatically: "arrow.triangle.2.circlepath"
        case .remove: "trash"
        }
    }
}

/// What an owned version's context menu offers, worked out once from the row's state — mirrors
/// `TitleMenu.make`'s shape.
enum VersionMenu {
    /// [Play This Version] · [Make Default (unless already the preferred one), Use Best
    /// Automatically (only when a preference is set)] · [Remove This Version…]. Empty groups are
    /// dropped so a divider never sits next to nothing; Remove is always the last group.
    static func make(isPreferred: Bool, hasPreference: Bool) -> [[VersionMenuItem]] {
        var middle: [VersionMenuItem] = []
        if !isPreferred { middle.append(.makeDefault) }
        if hasPreference { middle.append(.useBestAutomatically) }
        return [[.playThis], middle, [.remove]].filter { !$0.isEmpty }
    }
}
