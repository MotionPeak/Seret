import DebridCore
import DebridUI
import SwiftUI

/// The owner's Letterboxd watchlist (and their partner's, as one list) — a Plex page like Home and
/// Movies: a focus-driven preview header (the focused film's logo, year · runtime · ★ · genres,
/// its "In Library" / "Both of you" / "<Partner>'s pick" tags, its synopsis, over the ultrablur of
/// its backdrop) above rows of posters, with a big Surprise Me pill on the right of the header.
///
/// - Rows (`WatchlistRows`, in DebridUI): In Your Library · Recently Added · Highest Rated · You
///   Both Want to See · <Partner>'s Picks · a row per genre · Short Ones · Classics · Not Matched.
///   The rating, genre and runtime rows need TMDB details, which `WatchlistDetailsStore` fetches
///   (capped, store-owned) and keeps on disk — so they fill in on a first visit and are there at
///   once after. A row inserted above the focused one is answered by the page's realign.
/// - Every row ends in a See All tile that PUSHES the row's full grid (`WatchlistGridScreen`);
///   Menu pops back to the same tile.
/// - Surprise Me runs the spin (`WatchlistSpinScreen`); Sync beside it crawls Letterboxd now.
/// - A long-press on any film removes it, worded by whose list it is on.
struct WatchlistScreen: View {
    @Environment(AppSession.self) private var session
    /// False while this is a kept-alive page behind another one (the shell disables it).
    @Environment(\.isEnabled) private var isVisiblePage
    /// The side menu holds focus — the page must not move focus by itself then.
    /// Read when acting, never in the body — see `SideMenuFocusFlag`.
    @Environment(\.sideMenuFocus) private var sideMenuFocus
    /// Pushes the title Watch opens from the spin, through the shell (which owns the path and
    /// already routes titles — registering a destination here too would collide). A stable
    /// `ShellAction`, not a closure property: a closure input is unequal on every shell render, so
    /// the whole page — every row rebuilt from 256 films — re-ran on each press in the side menu
    /// (measured on the real Apple TV).
    @Environment(\.openBrowseDestination) private var openDestination
    /// OPTIONAL, deliberately — a non-optional `@Environment` read of an `@Observable` traps when it
    /// is absent. A film added or removed elsewhere reaches this page through its outcomes.
    @Environment(WatchlistMarks.self) private var watchlistMarks: WatchlistMarks?
    @State private var model: WatchlistModel?
    @State private var detailsStore: WatchlistDetailsStore?
    /// The launch preload's backstop: past this, details load even if Home never answers.
    @State private var preloadDeadlinePassed = false

    /// Home has answered its first build — or there is no Home to wait for.
    private var homeHasAnswered: Bool { session.home.map(\.hasBuiltForProfile) ?? true }
    /// Whether the details fetch may start. The page is built at launch and kept alive behind
    /// Home, and ~250 TMDB calls must not compete with Home's first paint — the same gate Movies
    /// and Shows wait on. On screen, it loads at once.
    private var mayLoad: Bool { isVisiblePage || homeHasAnswered || preloadDeadlinePassed }


#if DEBUG
    /// The model the `-uiPreview watchlist` harness renders instead of the session's, so the real
    /// screen can be screenshot-verified without a signed-in session or a Letterboxd account.
    var previewModel: WatchlistModel?
    /// The harness's art store (the unsigned preview session has none).
    var previewArt: TitleArtStore?
    /// The harness's details store (no session details provider either).
    var previewDetails: WatchlistDetailsStore?
    /// `-uiPreview watchlistremove`: this long after the page appears, the removal confirmation
    /// opens for the focused film — the long-press without the long press, since a keyboard long
    /// press leaves the Simulator one stale Select that swallows the dialog's next press.
    var previewRemoveFocusedAfter: Duration?
    private var art: TitleArtStore? { previewArt ?? session.titleArt }
#else
    private var art: TitleArtStore? { session.titleArt }
#endif

    /// Drives the preview header: tiles report focus, it publishes the one focus settles on.
    @State private var preview = FocusPreviewModel()
    /// The page's focus, followed without a `FocusState` of this screen's own — that re-rendered
    /// the screen, and rebuilt every rail, on each move along a rail (measured on Home).
    @State private var focusHandle = FocusBrowseHandle()
    /// What every focus move writes. Not observed: nothing in it is drawn.
    @State private var focusMemory = BrowseFocusMemory()
    /// The film focus is on, or was last on — so its header can be completed when its details land.
    @State private var focusedFilm = WatchlistFocusedFilm()
    /// Where focus was when it last left the page (the side menu, a pushed title or grid, the
    /// spin): coming back in lands there. Written once per departure, not per move.
    @State private var entryFocus: String?

    /// The spin in progress. Replacing it re-runs the reel, which is how "Spin Again" works.
    @State private var spin: WatchlistRandomizer.Spin?
    /// A film awaiting removal confirmation. Removing is the one destructive thing on this screen.
    @State private var pendingRemoval: WatchlistEntry?

    var body: some View {
        ZStack {
            CanvasBackground()
            if let model {
                page(model)
            } else {
                message("Set your Letterboxd username on your iPhone, in Seret → Settings.",
                        systemImage: "person.crop.circle.badge.questionmark")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fullScreenCover(item: $spin) { current in
            WatchlistSpinScreen(
                spin: current,
                details: session.detailsProvider,
                onWatch: { entry in
                    spin = nil
                    guard let item = MediaItem.watchlistTitle(entry, library: session.libraryStore)
                    else { return }
                    // Pushed a beat later: navigating while the cover is still on screen races its
                    // dismissal and the push is silently dropped.
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(350))
                        openDestination(.detail(item))
                    }
                },
                onSpinAgain: { spin = model?.spin() },
                onClose: { spin = nil })
        }
        // A Cancel leaves the film on the page: nothing to hand focus on from.
        .watchlistRemovalDialog(pending: $pendingRemoval, model: model,
                                onCancel: { focusMemory.actedOn = nil })
        // A See All tile's grid. Its own route type, so it collides with nothing the shell routes;
        // the grid reads the same model and details as this page, so a removal there shows here.
        .navigationDestination(for: WatchlistGridRoute.self) { route in
            if let model {
                WatchlistGridScreen(route: route, model: model, details: detailsStore, art: art)
            }
        }
        .task {
#if DEBUG
            if let previewModel {
                model = previewModel
                detailsStore = previewDetails
                if let delay = previewRemoveFocusedAfter {
                    try? await Task.sleep(for: delay)
                    // What a tile's long-press Remove does (`onRemove`).
                    focusMemory.actedOn = focusMemory.lastFocused
                    pendingRemoval = focusedFilm.entry
                }
                return
            }
#endif
            if model == nil { model = session.makeWatchlistModel() }
            if detailsStore == nil { detailsStore = session.makeWatchlistDetailsStore() }
            await model?.syncIfStale()
        }
        // A kept-alive page: films added or removed on a title page (or a tile elsewhere) while it
        // was behind another one are read back from the mirror — no crawl — when it is shown again,
        // and when a change is made while it is on screen under a pushed page.
        .onChange(of: isVisiblePage) { _, visible in
            if visible { Task { await model?.reloadCached() } }
        }
        .onChange(of: watchlistMarks?.lastOutcome?.event) { _, _ in
            Task { await model?.reloadCached() }
        }
    }

    // MARK: - The Plex page

    /// Stable ids for the page's non-rail focus targets and rows.
    enum PageID {
        static let surprise = "wl-surprise"
        static let sync = "wl-sync"
        static let emptyRow = "wl-empty"
    }

    static func tileID(_ row: String, _ entry: WatchlistEntry) -> String { "\(row)/\(entry.slug)" }
    static func seeAllID(_ row: String) -> String { "seeall/\(row)" }

    private func page(_ model: WatchlistModel) -> some View {
        let data = WatchlistPageData(model: model, details: detailsStore)
        let rows = data.rows
        let keys = focusKeys(rows, canSpin: model.canSpin)
        // Back where focus was while that is still on the page, else the first film of the row it
        // was in (or of the row that followed it, when that row has gone), else the first film —
        // or, with no films, the Sync pill. By row ID, not index: a row inserted above (details
        // arriving) must not shift the fallback onto a different row.
        let focusTarget = [focusMemory.lastFocused, entryFocus].compactMap { $0 }.first(where: keys.contains)
            ?? Self.firstTileID(near: focusedFilm.rowTrail, in: rows)
            ?? Self.firstTileID(near: rows.first.map { [$0.id] } ?? [], in: rows)
            ?? PageID.sync
        let first = rows.first?.entries.first
        // The first film's header, until a tile has had focus — keyed on what it shows, so its
        // synopsis and tags appear when they arrive.
        let firstSubject = first.map { data.subject(for: $0) }
        let placeholder = FocusPreviewPlaceholder(
            title: "Watchlist",
            hint: model.phase.isSyncing ? "Reading your watchlist…" : "Nothing on your watchlist yet.")
        // Every matched film, so the details store can fetch what it is missing — once the page
        // may load (see `mayLoad`), and again whenever it is shown (a failed film is retried
        // after its cool-off).
        let ids = model.entries.compactMap(\.tmdbID)
        let detailsKey = "\(ids.map(String.init).joined(separator: ","))/\(mayLoad)/\(isVisiblePage)"

        return FocusBrowsePage(preview: preview, art: art, initialFocus: focusTarget,
                               focusOnEntry: true, handle: focusHandle, placeholder: placeholder) {
            if rows.isEmpty {
                emptyRow(model)
            } else {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    // This row and the ones after it — where focus falls back to if it goes.
                    let trail = rows[index...].map(\.id)
                    PlexRail(title: row.title, subtitle: row.subtitle, id: row.id) {
                        ForEach(row.entries.prefix(WatchlistRows.railLimit)) { entry in
                            tile(entry, row: row, trail: trail, data: data)
                        }
                        // Every row has one, from the moment it exists — never a branch swap
                        // inside the lazy row.
                        seeAll(row, trail: trail)
                    }
                }
            }
        } accessory: {
            WatchlistHeaderControls(model: model, partnerName: data.partnerName,
                                    onSpin: { spin = model.spin() })
        }
        .onChange(of: firstSubject, initial: true) { _, subject in
            if let subject {
                guard !focusMemory.tileHasHadFocus else { return }
                preview.showImmediately(subject)
            } else {
                focusMemory.tileHasHadFocus = false
                preview.clear()
            }
        }
        // The focused film's details landed after it was focused (a first visit): complete its
        // header in place — same title, so nothing fades.
        .onChange(of: detailsStore?.generation) { _, _ in
            guard let entry = focusedFilm.entry, let shown = preview.shown else { return }
            let subject = data.subject(for: entry)
            if subject.id == shown.id, subject != shown { preview.showImmediately(subject) }
        }
        .task(id: detailsKey) {
            guard mayLoad else { return }
            await detailsStore?.ensure(ids)
        }
        .task {
            try? await Task.sleep(for: .seconds(8))
            preloadDeadlinePassed = true
        }
        // A removed film's tile goes; focus goes on to its neighbour (see `rehomeFocus`).
        .onChange(of: Self.tileOrder(rows)) { old, new in rehomeFocus(old: old, new: new) }
        .onChange(of: isVisiblePage) { _, visible in if !visible { cancelRehome() } }
        .onAppear { focusHandle.onChange = { focusChanged($0) } }
        .onDisappear { cancelRehome() }
    }

    private func tile(_ entry: WatchlistEntry, row: WatchlistRow, trail: [String],
                      data: WatchlistPageData) -> some View {
        let memory = focusMemory, preview = preview, film = focusedFilm, art = art
        let details = entry.tmdbID.flatMap { data.details[$0] }
        return WatchlistTile(entry: entry, owned: data.showsOwnedMark(entry, in: row.kind),
                             badge: data.badge(for: entry),
                             onRemove: {
                                 memory.actedOn = Self.tileID(row.id, $0)
                                 pendingRemoval = $0
                             },
                             onFocus: {
                                 memory.tileHasHadFocus = true
                                 film.rowTrail = trail
                                 film.entry = entry
                                 // The header's logo, rating and genres from the cache, at once.
                                 if let details, let id = entry.tmdbID {
                                     art?.seed(details.titleArt, for: .movie, tmdbID: id)
                                 }
                                 preview.focus(data.subject(for: entry))
                             })
            .plexFocusID(Self.tileID(row.id, entry))
    }

    private func seeAll(_ row: WatchlistRow, trail: [String]) -> some View {
        let film = focusedFilm
        return SeeAllTile(title: row.title, value: WatchlistGridRoute(rowID: row.id, title: row.title),
                          onFocus: { film.rowTrail = trail })
            .plexFocusID(Self.seeAllID(row.id))
    }

    /// No films (yet): the page names itself in the header and says why here; Sync is the focus.
    @ViewBuilder
    private func emptyRow(_ model: WatchlistModel) -> some View {
        Group {
            if model.phase.isSyncing {
                SeretLoader(label: "Reading your watchlist…")
            } else {
                VStack(spacing: 24) {
                    Image(systemName: "bookmark").font(.system(size: 54))
                        .foregroundStyle(Theme.Palette.textSecondary)
                    Text("Nothing on your watchlist yet.").sectionTitle()
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
            }
        }
        .padding(.top, 60)
        .frame(maxWidth: .infinity)
        .plexBrowseRow(id: PageID.emptyRow)
    }

    /// Centered full-canvas state, matching `LibraryScreen`'s.
    private func message(_ text: String, systemImage: String) -> some View {
        VStack(spacing: 28) {
            Image(systemName: systemImage).font(.system(size: 64)).foregroundStyle(Theme.Palette.textSecondary)
            Text(text).sectionTitle().multilineTextAlignment(.center).frame(maxWidth: 700)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Focus bookkeeping

    /// The first film of the first row in `trail` still on the page — the row focus was in, else
    /// the next one after it that survived; past the end, the last row.
    static func firstTileID(near trail: [String], in rows: [WatchlistRow]) -> String? {
        guard !trail.isEmpty, !rows.isEmpty else { return nil }
        let row = trail.lazy.compactMap { id in rows.first { $0.id == id } }.first ?? rows[rows.count - 1]
        return row.entries.first.map { tileID(row.id, $0) }
    }

    /// Every film tile's focus id, rail by rail, in screen order — See All tiles left out, so a
    /// rail is one run of keys sharing its row's prefix (what `RailFocusNeighbour` reads).
    static func tileOrder(_ rows: [WatchlistRow]) -> [String] {
        rows.flatMap { row in row.entries.prefix(WatchlistRows.railLimit).map { tileID(row.id, $0) } }
    }

    /// Hands focus on when the film that had it — or whose long-press menu had it — is gone.
    ///
    /// tvOS leaves NOTHING focused in that case: the confirmation closes, focus goes back to the
    /// tile it came from, and that tile is gone (measured: no ring anywhere, the header still
    /// showing the removed film, until the next press) — the same as Home's (`HomeScreen
    /// .rehomeFocus`). Only then, though: a tile leaving while focus is anywhere else must not pull
    /// focus. Retried, because tvOS ignores the write while the dialog is still animating away.
    private func rehomeFocus(old: [String], new: [String]) {
        guard !sideMenuFocus.holdsFocus, isVisiblePage else { return }
        let gone: String
        if let focused = focusHandle.focused, old.contains(focused), !new.contains(focused) {
            gone = focused
        } else if focusHandle.focused == nil, let acted = focusMemory.actedOn, !new.contains(acted) {
            gone = acted
        } else {
            return
        }
        focusMemory.actedOn = nil
        guard let next = RailFocusNeighbour.of(gone, old: old, new: new) else { return }
        cancelRehome()
        let handle = focusHandle, menu = sideMenuFocus
        focusMemory.rehomeTask = Task { @MainActor in
            for _ in 0..<20 {
                if menu.holdsFocus { return }
                handle.move(to: next)
                try? await Task.sleep(for: .milliseconds(100))
                if Task.isCancelled { return }
                if let now = handle.focused, now != gone { return }
            }
        }
    }

    private func cancelRehome() {
        focusMemory.rehomeTask?.cancel()
        focusMemory.rehomeTask = nil
    }

    /// Every focus id on the page: each rail's films and See All, and the header's pills.
    private func focusKeys(_ rows: [WatchlistRow], canSpin: Bool) -> Set<String> {
        var keys: Set<String> = [PageID.sync]
        if canSpin { keys.insert(PageID.surprise) }
        for row in rows {
            for entry in row.entries.prefix(WatchlistRows.railLimit) { keys.insert(Self.tileID(row.id, entry)) }
            keys.insert(Self.seeAllID(row.id))
        }
        return keys
    }

    /// As `BrowseScreen.focusChanged`: a move is remembered without re-rendering; leaving the page
    /// is recorded once it has settled, so coming back in lands where focus left from.
    private func focusChanged(_ key: String?) {
        focusMemory.departure?.cancel()
        if let key {
            // Focus has moved on to another view: the acted-on record is stale. Not when focus
            // is back on the acted-on tile itself — the menu → confirmation handover can pass
            // through it, and the record must survive that (a Cancel clears it instead).
            if key != focusMemory.actedOn { focusMemory.actedOn = nil }
            focusMemory.lastFocused = key
            return
        }
        let handle = focusHandle, memory = focusMemory, entry = $entryFocus
        memory.departure = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled, handle.focused == nil,
                  entry.wrappedValue != memory.lastFocused else { return }
            entry.wrappedValue = memory.lastFocused
        }
    }
}

/// The film the page's focus is on. A plain reference in `@State`, so writing it per focus move
/// never re-renders the page.
@MainActor
final class WatchlistFocusedFilm {
    var entry: WatchlistEntry?
    /// The row focus is (or was last) in, then the rows that followed it at the time.
    var rowTrail: [String] = []
}

/// A See All tile's value: which row's grid to push.
struct WatchlistGridRoute: Hashable {
    let rowID: String
    let title: String
}

/// One render's worth of what the page and its grids show — built in one place so a rail and the
/// grid behind its See All always agree.
@MainActor
struct WatchlistPageData {
    let rows: [WatchlistRow]
    /// Progressive — for the header, which should complete as soon as a film's details land.
    /// The rows are built from the store's `settled` map instead, so they never re-sort under
    /// focus while a first visit fills in.
    let details: [Int: WatchlistFilmDetails]
    /// Nil with no partner (or none configured): no Both / Picks rows, no badges, no tags.
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

    func badge(for entry: WatchlistEntry) -> String? {
        WatchlistRows.badge(for: entry, membership: membership, partnerName: partnerName)
    }

    /// The header's description of a film: its page's id (so the art store keys it), its cached
    /// synopsis and backdrop, and its tags. An unmatched film says so instead.
    func subject(for entry: WatchlistEntry) -> PreviewSubject {
        let title = WatchlistName.stripYear(from: entry.name)
        guard let item = MediaItem.watchlistMovie(entry) else {
            let stub = MediaItem(id: "watchlist:\(entry.slug)", kind: .movie, title: title,
                                 year: entry.year, sources: [], seasons: [], tmdbID: nil,
                                 posterPath: entry.posterPath)
            return PreviewSubject(item: stub, overview: nil, backdropPath: nil,
                                  tags: ["No TMDB match"], showsKind: false)
        }
        let info = entry.tmdbID.flatMap { details[$0] }
        return PreviewSubject(item: item, overview: info?.overview, backdropPath: info?.backdropPath,
                              tags: WatchlistRows.tags(for: entry, owned: isOwned(entry),
                                                       membership: membership,
                                                       partnerName: partnerName),
                              showsKind: false)
    }
}

extension WatchlistModel.Phase {
    var isSyncing: Bool {
        if case .syncing = self { return true }
        return false
    }
}

// MARK: - Header controls

/// The header's right side: Sync and the big Surprise Me pill, and one line of status under them.
/// Both rest as glass and turn solid white with focus, like every action on the TV.
///
/// The Sync button never leaves while a sync runs — only its label changes — so a focused Sync is
/// never swapped out from under the viewer.
private struct WatchlistHeaderControls: View {
    let model: WatchlistModel
    let partnerName: String?
    let onSpin: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 16) {
            HStack(spacing: 22) {
                Button { Task { await model.syncNow() } } label: {
                    Label(syncLabel, systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(SeretActionButtonStyle())
                .background(Capsule().fill(Self.backing))
                .plexFocusID(WatchlistScreen.PageID.sync)

                // Offered only when a spin has something to land on, rather than shown disabled —
                // a disabled control is unreachable on tvOS, so it would be a dead spot.
                if model.canSpin {
                    Button(action: onSpin) {
                        HStack(spacing: 20) {
                            Image(systemName: "die.face.5")
                                .font(.system(size: 34, weight: .semibold))
                            Text("Surprise Me")
                                .font(.seret(34, .bold))
                            Text(countLine)
                                .font(.seret(22, .medium))
                                .opacity(0.72)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(SeretActionButtonStyle())
                    .background(Capsule().fill(Self.backing))
                    .plexFocusID(WatchlistScreen.PageID.surprise)
                    .accessibilityLabel("Surprise Me, \(countLine)")
                }
            }
            status
        }
    }

    /// A shade under the glass, so a white label still reads over a bright backdrop (snow, a
    /// white poster). Behind the style's fill, so a focused pill is still solid white.
    private static let backing = Theme.Palette.shadeInk.opacity(0.4)

    private var syncLabel: String {
        switch model.phase {
        case .idle: "Sync"
        case .syncing: "Syncing…"
        case .failed: "Retry"
        }
    }

    /// "255 films · yours + Noga's", or "88 films" with no partner.
    private var countLine: String {
        let count = model.entries.count
        let films = count == 1 ? "1 film" : "\(count) films"
        guard let partnerName else { return films }
        return "\(films) · yours + \(partnerName)'s"
    }

    @ViewBuilder
    private var status: some View {
        switch model.phase {
        case .syncing(let done, let total):
            Text(total > 0 ? "Matching \(done) of \(total)…" : "Reading your watchlist…")
                .calloutText()
                .foregroundStyle(Theme.Palette.textSecondary)
                .statusPlate()
        case .failed(let message):
            // The palette's own error colour, not a raw `.red`.
            Text(message)
                .calloutText()
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(Theme.Palette.destructive)
                .statusPlate()
                .frame(maxWidth: 680, alignment: .trailing)
        case .idle:
            // A removal that could not reach Letterboxd is still gone from here, so this is the
            // only place the owner would ever learn it is half-done.
            if model.relayMessage != nil || model.partnerMessage != nil {
                VStack(alignment: .trailing, spacing: 10) { problems }
            } else if !model.canSpin, !model.entries.isEmpty {
                Text(countLine)
                    .calloutText()
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .statusPlate()
            }
        }
    }

    /// Both lines when both apply: a removal that did not reach Letterboxd, and a partner's list
    /// that could not be read are separate problems, and hiding one behind the other loses it.
    @ViewBuilder
    private var problems: some View {
        if let message = model.relayMessage {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .calloutText()
                .lineLimit(1)
                .foregroundStyle(Theme.Palette.destructive)
                .statusPlate()
                .frame(maxWidth: 680, alignment: .trailing)
        }
        if let message = model.partnerMessage {
            // The other person's list could not be read. Secondary, not red: the owner's own
            // list is fine and nothing they asked for failed.
            Text(message)
                .calloutText()
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(Theme.Palette.textSecondary)
                .statusPlate()
                .frame(maxWidth: 680, alignment: .trailing)
        }
    }
}

private extension View {
    /// A soft dark plate under a status line, so it reads over any backdrop — the header's art
    /// runs right behind it, and a bright plate (snow, a white set) washed the text out.
    func statusPlate() -> some View {
        padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Theme.Palette.shadeInk.opacity(0.55),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Tile

/// One watchlist film as a bare rail poster (a grid wraps it in `CaptionedPoster`): the poster, a
/// "Both" / "<Partner>" chip for a film on the partner's list, and the grey ✓ for one already in
/// the library.
///
/// A film that resolved to nothing is still shown — as a plain button, not a link. Hiding it would
/// make the count disagree with Letterboxd and give no way to find out why; making it a link would
/// promise a page that does not exist. Focusable regardless: tvOS scrolls by MOVING FOCUS, so a
/// tile with no focus target could never be scrolled to. Which kind a tile is never changes after
/// it is built (a film's match only changes with a sync, which rebuilds its rows).
struct WatchlistTile: View {
    let entry: WatchlistEntry
    let owned: Bool
    let badge: String?
    /// Long-press → remove. Raised rather than handled here so the confirmation belongs to the
    /// screen: a dialog owned by a tile dies with the tile the moment the row updates.
    var onRemove: (WatchlistEntry) -> Void = { _ in }
    /// Focus landed on the film — the page's header (or a grid's backdrop) follows it.
    var onFocus: () -> Void = {}

    @Environment(AppSession.self) private var session

    private var title: String { WatchlistName.stripYear(from: entry.name) }

    var body: some View {
        if let item = MediaItem.watchlistTitle(entry, library: session.libraryStore) {
            PosterTile(posterPath: entry.posterPath, title: title, chip: badge, owned: owned,
                       onFocus: onFocus, value: BrowseDestination.detail(item))
                .contextMenu { removeButton }
        } else {
            PosterTile(posterPath: entry.posterPath, title: title, chip: badge, owned: owned,
                       onFocus: onFocus, action: {})
                // Removable too — an unmatched film is the one you are most likely to want rid
                // of, since it is the one Seret can do nothing with.
                .contextMenu { removeButton }
        }
    }

    private var removeButton: some View {
        Button("Remove from Watchlist", systemImage: "minus.circle", role: .destructive) {
            onRemove(entry)
        }
    }
}

// MARK: - Removal

extension View {
    /// The removal confirmation, worded by whose list the film is on: only the owner's Letterboxd
    /// can be written, so a partner's film is hidden here and stays on theirs.
    func watchlistRemovalDialog(pending: Binding<WatchlistEntry?>, model: WatchlistModel?,
                                onCancel: @escaping () -> Void = {}) -> some View {
        confirmationDialog("Remove from watchlist?",
                           isPresented: .constant(pending.wrappedValue != nil),
                           titleVisibility: .visible,
                           presenting: pending.wrappedValue) { entry in
            Button("Remove", role: .destructive) {
                pending.wrappedValue = nil
                Task { await model?.remove(entry) }
            }
            Button("Cancel", role: .cancel) {
                pending.wrappedValue = nil
                onCancel()
            }
        } message: { entry in
            Text(model?.removalMessage(for: entry)
                 ?? "\(WatchlistName.stripYear(from: entry.name)) will be removed from your Letterboxd watchlist.")
        }
    }
}
