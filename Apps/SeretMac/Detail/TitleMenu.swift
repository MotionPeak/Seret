import DebridCore

/// One thing the title page's ⋯ menu can do.
enum TitleMenuItem: Hashable {
    case markWatched(Bool), markShowWatched(Bool), myList(adding: Bool), watchTrailer,
         addByMagnet, findOtherVersions, removeFromLibrary

    var title: String {
        switch self {
        case .markWatched(let watched): watched ? "Mark as Watched" : "Mark as Unwatched"
        case .markShowWatched(let watched): watched ? "Mark Show Watched" : "Mark Show Unwatched"
        case .myList(let adding): adding ? "Add to My List" : "Remove from My List"
        case .watchTrailer: "Watch Trailer"
        case .addByMagnet: "Add by Magnet\u{2026}"
        case .findOtherVersions: "Find Other Versions\u{2026}"
        case .removeFromLibrary: "Remove from Library\u{2026}"
        }
    }

    var symbol: String {
        switch self {
        case .markWatched(let watched), .markShowWatched(let watched):
            watched ? "checkmark.circle" : "circle"
        case .myList(let adding): adding ? "bookmark" : "bookmark.slash"
        case .watchTrailer: "play.rectangle"
        case .addByMagnet: "link"
        case .findOtherVersions: "arrow.triangle.2.circlepath"
        case .removeFromLibrary: "trash"
        }
    }
}

/// What the title page's ⋯ menu offers, worked out once from the page's state — mirrors
/// `PosterActions.make`'s shape, one level up (a whole title rather than one poster).
enum TitleMenu {
    /// Groups, with a divider between each: [marks, My List?, Watch Trailer?] ·
    /// [Add by Magnet?, Find Other Versions? (films only)] · [Remove? (owned)]. Empty groups are
    /// dropped so a divider never sits next to nothing.
    static func make(kind: MediaKind, owned: Bool, watched: Bool, inMyList: Bool, canMyList: Bool,
                     hasTrailer: Bool, canMagnet: Bool, canFindVersions: Bool) -> [[TitleMenuItem]] {
        var marksGroup: [TitleMenuItem] = []
        switch kind {
        case .movie:
            marksGroup.append(.markWatched(!watched))
        case .show:
            // Both directions, always — the same rule `PosterActions.make` uses for a show:
            // there is no single "watched" state for a whole series worth toggling.
            marksGroup.append(.markShowWatched(true))
            marksGroup.append(.markShowWatched(false))
        }
        if canMyList { marksGroup.append(.myList(adding: !inMyList)) }
        if hasTrailer { marksGroup.append(.watchTrailer) }

        var addGroup: [TitleMenuItem] = []
        if canMagnet { addGroup.append(.addByMagnet) }
        if kind == .movie, canFindVersions { addGroup.append(.findOtherVersions) }

        var removeGroup: [TitleMenuItem] = []
        if owned { removeGroup.append(.removeFromLibrary) }

        return [marksGroup, addGroup, removeGroup].filter { !$0.isEmpty }
    }
}
