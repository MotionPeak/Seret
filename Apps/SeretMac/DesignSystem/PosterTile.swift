import DebridCore
import DebridUI
import SwiftUI

/// What a poster stands for, built once from a library item (owned) or a TMDB hit (owned or not) —
/// the one shape every grid and rail's `PosterTile` renders from.
struct PosterTileModel: Identifiable, Equatable {
    let id: String
    let title: String
    let caption: String
    let posterURL: URL?
    let kind: MediaKind
    let owned: MediaItem?
    let hit: SearchHit?
    /// What Open pushes: the owned item if there is one, else a placeholder built from `hit`.
    let page: MediaItem
    let watchlistFilm: WatchlistFilm?
    let isCAM: Bool

    static func library(_ item: MediaItem) -> PosterTileModel {
        PosterTileModel(id: item.id, title: item.title, caption: item.year.map(String.init) ?? "",
                        posterURL: TMDBClient.imageURL(path: item.posterPath, size: "w342"),
                        kind: item.kind, owned: item, hit: nil, page: item,
                        watchlistFilm: WatchlistFilm(item: item), isCAM: false)
    }

    /// `owned` is only ever the library's item for the SAME kind — a movie and a show can share a
    /// TMDB id, and `LibraryStore.ownedItem(tmdbID:)` is kind-blind.
    @MainActor
    static func hit(_ hit: SearchHit, library: LibraryStore?, isCAM: Bool) -> PosterTileModel {
        let owned = library?.ownedItem(tmdbID: hit.result.id).flatMap { $0.kind == hit.kind ? $0 : nil }
        return PosterTileModel(id: hit.contentKey, title: hit.result.displayTitle,
                               caption: hit.result.year.map(String.init) ?? "",
                               posterURL: TMDBClient.imageURL(path: hit.result.posterPath, size: "w342"),
                               kind: hit.kind, owned: owned, hit: hit,
                               page: owned ?? .placeholder(for: hit),
                               watchlistFilm: WatchlistFilm(hit: hit), isCAM: isCAM)
    }
}

/// A poster's badge + decoration, worked out by the caller from whatever it has on hand (a
/// `LibraryStore.watchState(for:)` for an owned tile, `TileWatchMarks.isWatched(_:)` for a hit).
struct PosterTileState: Equatable {
    let badge: WatchBadge
    var decor: PosterDecor = PosterDecor()
}

/// The one poster used by every grid and rail: tilts toward the pointer, catches a glare, gains
/// badges and a gold rim, fades in its quick actions, and offers every one of those (plus the rest)
/// on right-click.
struct PosterTile: View {
    let model: PosterTileModel
    let state: PosterTileState
    let actions: PosterActions
    let perform: (PosterAction, PosterTileModel) -> Void
    /// Forces the tilt/hover look on — harness only, so it can be screenshotted without a pointer.
    var forcedPointer: UnitPoint? = nil
    /// Harness only (`-uiPreview flight`/`flightback`): fixes this tile's identity to a known value
    /// so a pinned `HeroFlight` can be built pointing at exactly this tile.
    var forcedTileID: UUID? = nil

    @State private var pointer: UnitPoint?
    /// A fresh identity every time this tile mounts — a lazy grid recycling the view underneath a
    /// stable `id` would otherwise leave a flight pointed at whatever cell happens to sit there now.
    @State private var generatedTileID = UUID()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(WatchlistMarks.self) private var watchlistMarks: WatchlistMarks?
    @Environment(ShellModel.self) private var shell: ShellModel?

    private var tileID: UUID { forcedTileID ?? generatedTileID }

    private var activePointer: UnitPoint? { forcedPointer ?? pointer }
    private var isHovered: Bool { activePointer != nil }
    private var watchlistInFlight: Bool {
        model.watchlistFilm.map { watchlistMarks?.isInFlight(tmdbID: $0.tmdbID) ?? false } ?? false
    }
    /// This tile IS the flight currently in the air — hidden so the real card never shows twice at
    /// once alongside the flyer (Decision 10). Clears itself the instant the flight does (forward:
    /// stays hidden — the page it flew to has replaced this one; back: `landFlight` clears `flight`
    /// entirely once it lands, which is exactly when the real tile should reappear).
    private var isFlightSource: Bool { shell?.flight?.tileID == tileID }

    var body: some View {
        Button { openWithFlightSource() } label: {
            PosterCard(title: model.title, caption: model.caption, posterURL: model.posterURL,
                      badge: state.badge, pointer: activePointer, decor: state.decor)
        }
        .buttonStyle(.plain)
        // Built only for the hovered tile. Every tile used to carry its own hidden bar — three
        // buttons, each with hover tracking and a tooltip — which made a row of tiles expensive to
        // bring on screen while scrolling.
        .overlay(alignment: .top) {
            if isHovered {
                QuickActionsBar(actions: actions.hover, isWatchlistInFlight: watchlistInFlight) { action in
                    perform(action, model)
                }
                .frame(width: PosterCard.posterSize.width, height: PosterCard.posterSize.height, alignment: .bottom)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 8)))
            }
        }
        .animation(Theme.Motion.quick, value: isHovered)
        .onContinuousHover(coordinateSpace: .local) { phase in
            if case .active(let p) = phase {
                pointer = UnitPoint(x: p.x / PosterCard.posterSize.width, y: p.y / PosterCard.posterSize.height)
            } else {
                pointer = nil
            }
        }
        .contextMenu { menuContent }
        .opacity(isFlightSource ? 0 : 1)
        .allowsHitTesting(!isFlightSource)
        // The flight needs this tile's frame only at the moment it is clicked (and to fly back to,
        // unchanged underneath the page it opened), and a click always comes from a pointer that
        // is over the tile — so it is measured only while hovered, not by every tile on every
        // scroll frame.
        .background {
            if isHovered {
                Color.clear
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(ShellSpace.window)) } action: { frame in
                        shell?.tileFrames[tileID] = frame
                    }
            }
        }
    }

    /// What both the click and the menu's Open take: the tile hands the shell its own frame + art
    /// right before the push, so a flight (if one starts) has a snapshot from the instant of the tap.
    private func openWithFlightSource() {
        // No recorded frame (never laid out in the window space) → no source → the page cross-fades.
        if let frame = shell?.tileFrames[tileID] {
            shell?.pendingFlightSource = FlightSource(tileID: tileID, frame: frame, posterURL: model.posterURL)
        }
        perform(.open, model)
    }

    @ViewBuilder private var menuContent: some View {
        ForEach(Array(actions.menu.enumerated()), id: \.offset) { index, group in
            ForEach(group, id: \.self) { action in
                Button {
                    if action == .open { openWithFlightSource() } else { perform(action, model) }
                } label: {
                    Label(action.title, systemImage: action.symbol)
                }
            }
            if index < actions.menu.count - 1 { Divider() }
        }
    }
}

/// The quick-actions row that fades in over a hovered poster's bottom edge: up to three 34 pt
/// glass circles, each glowing gold under the pointer.
struct QuickActionsBar: View {
    let actions: [PosterAction]
    var isWatchlistInFlight: Bool = false
    let perform: (PosterAction) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(actions, id: \.self) { action in
                QuickActionButton(action: action, dimmed: isWatchlistAction(action) && isWatchlistInFlight) {
                    perform(action)
                }
            }
        }
        .padding(.bottom, 12)
    }

    private func isWatchlistAction(_ action: PosterAction) -> Bool {
        if case .watchlist = action { return true }
        return false
    }
}

private struct QuickActionButton: View {
    let action: PosterAction
    let dimmed: Bool
    let onTap: () -> Void

    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onTap) {
            Image(systemName: action.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(hovering ? Theme.Palette.onGold : Color.white)
                .frame(width: 34, height: 34)
                .background(fill)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .scaleEffect(hovering && !reduceMotion ? 1.14 : 1)
        .opacity(dimmed ? 0.4 : 1)
        .disabled(dimmed)
        .help(action.title)
        .animation(Theme.Motion.quick, value: hovering)
        .onHover { hovering = $0 }
    }

    @ViewBuilder private var fill: some View {
        if hovering {
            Circle().fill(Theme.Palette.goldGradient)
        } else {
            Circle().fill(Color.black.opacity(0.6))
            Circle().fill(.ultraThinMaterial)
        }
    }
}
