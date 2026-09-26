import DebridCore
import DebridUI
import SwiftUI

/// A film's franchise, numbered — the current film ringed and never opens itself again, owned
/// parts carrying M2's owned disc (Decision 9: ✓ already means watched everywhere, so a collection
/// part you own gets the disc, not a checkmark).
struct FranchiseRail: View {
    let store: DetailStore
    let franchise: Franchise

    @Environment(AppSession.self) private var session: AppSession?
    @Environment(ShellModel.self) private var shell: ShellModel?
    @Environment(LibraryStore.self) private var injectedLibrary: LibraryStore?
    @Environment(TileWatchMarks.self) private var marks: TileWatchMarks?
    @Environment(WatchlistMarks.self) private var watchlist: WatchlistMarks?

    private var library: LibraryStore? { injectedLibrary ?? session?.libraryStore }
    private var performer: PosterActionPerformer {
        PosterActionPerformer(session: session, shell: shell, library: library, marks: marks, watchlist: watchlist)
    }
    private var hits: [SearchHit] { franchise.parts.map { SearchHit(result: $0, kind: .movie) } }

    var body: some View {
        PosterRail(title: franchise.name, items: hits) { hit in tile(hit) }
            .task(id: hits.map(\.id)) { await marks?.load(hits) }
    }

    private func tile(_ hit: SearchHit) -> some View {
        let model = PosterTileModel.hit(hit, library: library, isCAM: false)
        let watched = marks?.isWatched(hit) ?? false
        let isCurrent = hit.result.id == store.item.tmdbID
        let number = (franchise.parts.firstIndex { $0.id == hit.result.id } ?? 0) + 1
        let badge: WatchBadge = watched ? .watched : .none
        let decor = PosterDecor(owned: model.owned != nil, dimsWatched: true, number: number, isCurrent: isCurrent)
        // The current film loses its quick actions (Decision 9) — the ring already says "you're
        // here", and `PosterActionPerformer` refuses to re-open it even from the menu's Open.
        let actions: PosterActions = isCurrent
            ? PosterActions(hover: [], menu: [[.open]])
            : .make(kind: .movie, owned: model.owned != nil, watched: watched, onWatchlist: false)
        return PosterTile(model: model, state: PosterTileState(badge: badge, decor: decor),
                          actions: actions, perform: performer.perform)
    }
}

/// Up to 15 cast members, headshot first — a round photo (initials when there is none), the name
/// and character, opening a `PersonPage` on click or right-click.
struct CastRail: View {
    let store: DetailStore

    @Environment(ShellModel.self) private var shell: ShellModel?
    @Environment(\.pageLeadingInset) private var pageLeadingInset

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CAST")
                .font(Theme.Typo.label())
                .tracking(1.5)
                .foregroundStyle(Theme.Palette.gold)
                .padding(.leading, pageLeadingInset)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 20) {
                    ForEach(store.cast.prefix(15)) { member in
                        CastCard(member: member) { open(member) }
                    }
                }
                .padding(.vertical, 12)
            }
            .contentMargins(.leading, pageLeadingInset, for: .scrollContent)
            .contentMargins(.trailing, 28, for: .scrollContent)
            .scrollClipDisabled()
            .scrollIndicators(.hidden)
        }
    }

    private func open(_ member: TMDBCastMember) {
        shell?.open(.person(TMDBPersonRef(id: member.id, name: member.name)))
    }
}

private struct CastCard: View {
    let member: TMDBCastMember
    let onOpen: () -> Void

    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onOpen) {
            VStack(spacing: 8) {
                headshot
                Text(member.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)
                Text(member.character?.isEmpty == false ? member.character! : " ")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .lineLimit(1)
            }
            .frame(width: 96)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu { Button("Open", action: onOpen) }
    }

    private var headshot: some View {
        RemoteImage(url: TMDBClient.imageURL(path: member.profilePath, size: "w185")) { initials }
            .frame(width: 84, height: 84)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(hovering ? Theme.Palette.gold.opacity(0.9) : .clear, lineWidth: 1.5))
            .scaleEffect(hovering && !reduceMotion ? 1.07 : 1)
            .animation(Theme.Motion.quick, value: hovering)
    }

    private var initials: some View {
        Circle().fill(Theme.Palette.surface2).overlay {
            Text(initialsText)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private var initialsText: String {
        member.name.split(separator: " ").compactMap(\.first).prefix(2).map(String.init).joined()
    }
}

/// TMDB's recommendations for this title, through the exact same tile every other rail uses.
struct MoreLikeThisRail: View {
    let store: DetailStore

    @Environment(AppSession.self) private var session: AppSession?
    @Environment(ShellModel.self) private var shell: ShellModel?
    @Environment(LibraryStore.self) private var injectedLibrary: LibraryStore?
    @Environment(TileWatchMarks.self) private var marks: TileWatchMarks?
    @Environment(WatchlistMarks.self) private var watchlist: WatchlistMarks?

    private var library: LibraryStore? { injectedLibrary ?? session?.libraryStore }
    private var performer: PosterActionPerformer {
        PosterActionPerformer(session: session, shell: shell, library: library, marks: marks, watchlist: watchlist)
    }
    private var hits: [SearchHit] { store.similar.map { SearchHit(result: $0, kind: store.item.kind) } }

    var body: some View {
        PosterRail(title: "More Like This", items: hits) { hit in tile(hit) }
            .task(id: hits.map(\.id)) { await marks?.load(hits) }
    }

    private func tile(_ hit: SearchHit) -> some View {
        let model = PosterTileModel.hit(hit, library: library, isCAM: false)
        let watched = marks?.isWatched(hit) ?? false
        let onWatchlist = model.watchlistFilm.map { watchlist?.contains(tmdbID: $0.tmdbID) ?? false } ?? false
        let badge: WatchBadge = watched ? .watched : .none
        let decor = PosterDecor(owned: model.owned != nil, onWatchlist: onWatchlist, dimsWatched: true)
        return PosterTile(model: model, state: PosterTileState(badge: badge, decor: decor),
                          actions: .make(kind: hit.kind, owned: model.owned != nil, watched: watched, onWatchlist: onWatchlist),
                          perform: performer.perform)
    }
}
