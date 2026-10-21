import DebridCore
import DebridUI
import SwiftUI

/// One render's worth of what the Watchlist page and its See All grids show — built in one place
/// so a rail and the grid behind its See All always agree (the Apple TV's `WatchlistPageData`,
/// without the focus header it also feeds there).
///
/// The rows are built from the details store's `settled` map, never the progressive one: building
/// them from a half-filled map re-sorted Highest Rated and re-cut the genre rows on every batch of
/// a first visit, so posters would slide about under the viewer's finger.
@MainActor
struct WatchlistPageData {
    let rows: [WatchlistRow]
    /// Progressive — for what describes ONE film (the featured card's backdrop and line), which
    /// should complete as soon as that film's details land.
    let details: [Int: WatchlistFilmDetails]
    /// Nil with no partner (or none configured): no Both / Picks rows, no chips.
    let membership: WatchlistMembership?
    let partnerName: String?
    private let owned: Set<String>

    init(model: WatchlistModel, details store: WatchlistDetailsStore?) {
        let status = model.combinedStatus
        partnerName = status.partnerName
        membership = status.partnerName == nil ? nil : status.membership
        details = store?.details ?? [:]
        let entries = model.entries
        owned = Set(entries.filter(model.isOwned).map(\.slug))
        let owned = owned
        rows = WatchlistRows.build(entries: entries, details: store?.settled ?? [:],
                                   isOwned: { owned.contains($0.slug) },
                                   membership: membership, partnerName: partnerName)
    }

    func isOwned(_ entry: WatchlistEntry) -> Bool { owned.contains(entry.slug) }

    /// The grey ✓, except inside In Your Library — where every film has it, so it says nothing.
    func showsOwnedMark(_ entry: WatchlistEntry, in row: WatchlistRow.Kind) -> Bool {
        row != .library && isOwned(entry)
    }

    /// "Both", or the partner's name — the chip on the poster.
    func badge(for entry: WatchlistEntry) -> String? {
        WatchlistRows.badge(for: entry, membership: membership, partnerName: partnerName)
    }

    /// The featured card's line: "In Library · ready to play", "Both of you · 1999 · 2h 2m",
    /// else what TMDB says about it.
    func line(for entry: WatchlistEntry) -> String {
        var parts = WatchlistRows.tags(for: entry, owned: isOwned(entry), membership: membership,
                                       partnerName: partnerName)
        if isOwned(entry) {
            parts.append("ready to play")
            return parts.joined(separator: " · ")
        }
        if let year = entry.year { parts.append(String(year)) }
        if let info = entry.tmdbID.flatMap({ details[$0] }) {
            if let runtime = info.runtimeMinutes, runtime > 0 { parts.append(Self.runtime(runtime)) }
            if let vote = info.voteAverage, vote > 0 { parts.append("★ " + String(format: "%.1f", vote)) }
        }
        return parts.joined(separator: " · ")
    }

    /// The page's count: "255 films · yours + Noga's", or "88 films" with no partner.
    static func countLine(_ count: Int, partnerName: String?) -> String {
        let films = count == 1 ? "1 film" : "\(count) films"
        guard let partnerName else { return films }
        return "\(films) · yours + \(partnerName)'s"
    }

    private static func runtime(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}

// MARK: - Tile

/// One watchlist film as a poster: the art, a "Both" / "<Partner>" chip for a film on the
/// partner's list, the grey ✓ for one already in the library, the white ✓ once watched.
///
/// A tap opens its title page — the library's own item when the film is owned (see
/// `MediaItem.watchlistTitle`). A film TMDB could not match is still shown (hiding it would make
/// the count disagree with Letterboxd) but opens nothing; its long-press still removes it, since it
/// is the one Seret can do nothing with.
struct WatchlistFilmTile: View {
    let entry: WatchlistEntry
    let owned: Bool
    let badge: String?
    var width: CGFloat?
    var showsTitle = false
    /// Raised rather than handled here, so the confirmation belongs to the screen: a dialog owned
    /// by a tile dies with the tile the moment its row updates.
    let onRemove: (WatchlistEntry) -> Void
    /// False on Home, whose rows are the day's short list: the Watchlist page owns removal.
    var allowsRemove = true

    @Environment(AppSession.self) private var session
    @Environment(AppRouter.self) private var router
    /// OPTIONAL, deliberately — see `HitTile`.
    @Environment(TileWatchMarks.self) private var marks: TileWatchMarks?

    var body: some View {
        let item = MediaItem.watchlistTitle(entry, library: session.libraryStore)
        let watched = WatchlistFilmMarks.isWatched(entry, item: item, session: session, marks: marks)
        let title = WatchlistName.stripYear(from: entry.name)
        let poster = PosterTile(posterPath: entry.posterPath, title: title, width: width,
                                chip: badge, watched: watched, owned: owned,
                                showsTitle: showsTitle)
        Group {
            if let item {
                Button { router.detail = item } label: { poster }
                    .pressable()
            } else {
                poster
                    .overlay(alignment: .bottom) {
                        if !showsTitle {
                            Text("No TMDB match")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.Palette.textTertiary)
                                .padding(.bottom, 8)
                        }
                    }
                    .accessibilityHint("Couldn't match this film on TMDB")
            }
        }
        .contextMenu {
            WatchlistFilmActions(entry: entry, item: item, watched: watched,
                                 open: { if let item { router.detail = item } },
                                 onRemove: allowsRemove ? onRemove : nil)
        }
    }
}

/// A watchlist film's long-press: open it, mark it (un)watched, take it off the watchlist.
struct WatchlistFilmActions: View {
    let entry: WatchlistEntry
    let item: MediaItem?
    let watched: Bool
    let open: () -> Void
    /// Nil: no Remove (Home's rows).
    let onRemove: ((WatchlistEntry) -> Void)?

    @Environment(AppSession.self) private var session
    @Environment(TileWatchMarks.self) private var marks: TileWatchMarks?

    var body: some View {
        if item != nil {
            Button("Open", systemImage: "info.circle", action: open)
            Button(watched ? "Mark Unwatched" : "Mark Watched",
                   systemImage: watched ? "checkmark.circle.fill" : "checkmark.circle") {
                WatchlistFilmMarks.toggle(entry, item: item, watched: watched, session: session,
                                          marks: marks)
            }
        }
        if let onRemove {
            Button("Remove from Watchlist", systemImage: "minus.circle", role: .destructive) {
                onRemove(entry)
            }
        }
    }
}

/// Watched state for a watchlist film: the library's own when the film is owned, else the browse
/// tiles' shared marks — the same two paths the library menu and a search tile use.
@MainActor
enum WatchlistFilmMarks {
    static func hit(_ entry: WatchlistEntry) -> SearchHit? {
        guard let id = entry.tmdbID else { return nil }
        let result = TMDBSearchResult(id: id, title: WatchlistName.stripYear(from: entry.name),
                                      name: nil, releaseDate: entry.year.map { "\($0)-01-01" },
                                      firstAirDate: nil, posterPath: entry.posterPath,
                                      overview: nil, voteAverage: nil)
        return SearchHit(result: result, kind: .movie)
    }

    static func hits(_ entries: [WatchlistEntry]) -> [SearchHit] { entries.compactMap(hit) }

    static func isWatched(_ entry: WatchlistEntry, item: MediaItem?, session: AppSession,
                          marks: TileWatchMarks?) -> Bool {
        if let item, !item.sources.isEmpty,
           let state = session.libraryStore?.watchState(for: item) {
            return state.finished
        }
        guard let hit = hit(entry) else { return false }
        return marks?.isWatched(hit) ?? false
    }

    /// The tick flips at once; the write follows.
    static func toggle(_ entry: WatchlistEntry, item: MediaItem?, watched: Bool,
                       session: AppSession, marks: TileWatchMarks?) {
        // Not before a profile has resolved — a row written under "" is one nothing adopts.
        guard let profileID = session.activeProfileID, let hit = hit(entry) else { return }
        marks?.set(!watched, for: hit)
        if let item, !item.sources.isEmpty, let store = session.libraryStore {
            Task { await store.setWatched(!watched, for: item) }
        } else {
            Task {
                await session.watchStore?.setWatched(!watched, contentKey: hit.contentKey,
                                                     sourceKey: "", profileID: profileID)
            }
        }
    }
}

// MARK: - Removal

extension View {
    /// The removal confirmation, worded by whose list the film is on (`removalMessage`, shared with
    /// the Apple TV): only the owner's Letterboxd can be written, so a film only the partner holds
    /// is hidden here and stays on theirs — said before the owner agrees, not after.
    func watchlistRemovalDialog(pending: Binding<WatchlistEntry?>,
                                model: WatchlistModel?) -> some View {
        // An alert, not a confirmation dialog: with no source view to point at, iPad pinned the
        // dialog's popover to the page's edge, beside the sidebar. Same as the library's removal.
        alert("Remove from watchlist?",
              isPresented: Binding(get: { pending.wrappedValue != nil },
                                   set: { if !$0 { pending.wrappedValue = nil } }),
              presenting: pending.wrappedValue) { entry in
            Button("Remove", role: .destructive) {
                pending.wrappedValue = nil
                Task { await model?.remove(entry) }
            }
            Button("Cancel", role: .cancel) { pending.wrappedValue = nil }
        } message: { entry in
            Text(model?.removalMessage(for: entry)
                 ?? "\(WatchlistName.stripYear(from: entry.name)) will be removed from your Letterboxd watchlist.")
        }
    }
}

/// A row's See All: which row's grid to push.
struct WatchlistGridRoute: Hashable {
    let rowID: String
    let title: String
}
