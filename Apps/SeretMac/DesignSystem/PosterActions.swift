import DebridCore

/// One thing a poster's hover row or right-click menu can do.
enum PosterAction: Hashable {
    case play, open, watchlist(adding: Bool), markWatched(Bool), markShowWatched(Bool), removeFromLibrary

    var title: String {
        switch self {
        case .play: "Play"
        case .open: "Open"
        case .watchlist(let adding): adding ? "Add to Watchlist" : "Remove from Watchlist"
        case .markWatched(let watched): watched ? "Mark as Watched" : "Mark as Unwatched"
        case .markShowWatched(let watched): watched ? "Mark Show Watched" : "Mark Show Unwatched"
        case .removeFromLibrary: "Remove from Library…"
        }
    }

    var symbol: String {
        switch self {
        case .play: "play.fill"
        case .open: "arrow.up.right.square"
        case .watchlist(let adding): adding ? "bookmark" : "bookmark.slash"
        case .markWatched(let watched): watched ? "checkmark.circle" : "circle"
        case .markShowWatched(let watched): watched ? "checkmark.circle" : "circle"
        case .removeFromLibrary: "trash"
        }
    }
}

/// What a poster offers, worked out once from its state — the hover row (a short list of quick
/// actions) and the right-click menu (everything the hover row offers, plus the rest). A test
/// proves the hover row is always a subset of the menu, so nothing hidden on hover surprises a
/// right-click.
struct PosterActions: Equatable {
    /// In order: Play (owned titles only) · Watchlist (films only) · Mark (a film toggles; a show
    /// offers only the direction that is useful right now).
    let hover: [PosterAction]
    /// Groups, drawn with a divider between each: [Play?, Open] · [Watchlist?, mark(s)] · [Remove?].
    let menu: [[PosterAction]]

    static func make(kind: MediaKind, owned: Bool, watched: Bool, onWatchlist: Bool) -> PosterActions {
        var hover: [PosterAction] = []
        if owned { hover.append(.play) }
        if kind == .movie { hover.append(.watchlist(adding: !onWatchlist)) }
        switch kind {
        case .movie: hover.append(.markWatched(!watched))
        case .show: hover.append(.markShowWatched(!watched))
        }

        var firstGroup: [PosterAction] = []
        if owned { firstGroup.append(.play) }
        firstGroup.append(.open)

        var secondGroup: [PosterAction] = []
        if kind == .movie { secondGroup.append(.watchlist(adding: !onWatchlist)) }
        switch kind {
        case .movie:
            secondGroup.append(.markWatched(!watched))
        case .show:
            secondGroup.append(.markShowWatched(true))
            secondGroup.append(.markShowWatched(false))
        }

        var groups = [firstGroup, secondGroup]
        if owned { groups.append([.removeFromLibrary]) }

        return PosterActions(hover: hover, menu: groups)
    }
}
