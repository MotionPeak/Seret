import DebridCore
import DebridUI
import SwiftUI

/// The owner's Letterboxd watchlist — and their partner's, as one list — as the Apple TV draws it:
/// one page of rows (g4), under a glass page header with the film count and a glass Surprise Me
/// pill.
///
/// - A featured card on top: the first film of the first row, its backdrop, "In Library · ready
///   to play".
/// - Rows (`WatchlistRows`, shared with the TV): In Your Library · Recently Added · Highest Rated ·
///   You Both Want to See · <Partner>'s Picks · a row per genre · Short Ones · Classics · Not
///   Matched. The rating, genre and runtime rows need TMDB details, which `WatchlistDetailsStore`
///   fetches (capped, store-owned) and keeps on disk. Rows are built from its SETTLED snapshot, so
///   they never reshuffle while the viewer is looking; they fill in once a pass is over.
/// - Every row has a See All, in its header and as its last tile — the row's full grid
///   (`WatchlistGridScreen`, adaptive columns).
/// - Surprise Me runs the Cover Flow spin (`WatchlistSpinScreen`) in a sheet a swipe dismisses.
/// - A long-press opens the film, marks it watched, or removes it — worded by whose list it is on.
/// - Pull to refresh crawls Letterboxd now.
struct WatchlistScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(\.horizontalSizeClass) private var hSize
    /// OPTIONAL, deliberately — a non-optional `@Environment` read of an `@Observable` traps when it
    /// is absent. A film added or removed elsewhere reaches this page through its outcomes.
    @Environment(WatchlistMarks.self) private var watchlistMarks: WatchlistMarks?
    @Environment(TileWatchMarks.self) private var marks: TileWatchMarks?

    @State private var model: WatchlistModel?
    @State private var detailsStore: WatchlistDetailsStore?
    /// Nil until read: whether a Letterboxd username is set at all.
    @State private var connected: Bool?
    /// The spin in progress (the sheet is up while this is set).
    @State private var spin: WatchlistRandomizer.Spin?
    /// A film awaiting removal confirmation — the one destructive thing on this page.
    @State private var pendingRemoval: WatchlistEntry?
    @State private var showingSettings = false

#if DEBUG
    @Environment(\.uiPreviewStores) private var preview
    private var details: MediaDetailsProviding? { preview?.watchlistArt ?? session.detailsProvider }
#else
    private var details: MediaDetailsProviding? { session.detailsProvider }
#endif

    var body: some View {
        ZStack {
            CanvasBackground()
            content
        }
        .glassPageHeader("Watchlist", subtitle: countLine) {
            if let model, model.canSpin {
                Button { spin = model.spin() } label: {
                    Label("Surprise Me", systemImage: "die.face.5")
                }
                .buttonStyle(GlassPillButtonStyle())
                .accessibilityHint("Picks a film off your watchlist at random")
            }
        }
        .navigationDestination(for: WatchlistGridRoute.self) { route in
            if let model {
                WatchlistGridScreen(route: route, model: model, details: detailsStore)
            }
        }
        .watchlistRemovalDialog(pending: $pendingRemoval, model: model)
        .sheet(item: $spin) { current in
            WatchlistSpinScreen(spin: current, details: details,
                                respin: { model?.spin() },
                                onWatch: { entry in
                                    spin = nil
                                    guard let item = MediaItem.watchlistTitle(entry, library: session.libraryStore)
                                    else { return }
                                    // A beat later: presenting the title while the sheet is still
                                    // going away races its dismissal and the cover never shows.
                                    Task { @MainActor in
                                        try? await Task.sleep(for: .milliseconds(450))
                                        router.detail = item
                                    }
                                },
                                onClose: { spin = nil })
        }
        .sheet(isPresented: $showingSettings, onDismiss: { build(force: true) }) {
            NavigationStack {
                SettingsView()
                    .environment(session)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showingSettings = false }.tint(Theme.Palette.focus)
                        }
                    }
            }
        }
        // Keyed on the library: the model needs it (ownership), and it exists only once signed in.
        .task(id: session.libraryStore == nil) {
            build(force: false)
#if DEBUG
            if let script = preview?.watchlistScript {
                await runScript(script)
                return
            }
            // `-watchlistAutoSpin YES` on the real app: Surprise Me without a finger.
            if UserDefaults.standard.bool(forKey: "watchlistAutoSpin") {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(4))
                    spin = model?.spin()
                }
            }
#endif
            await model?.syncIfStale()
        }
        // A film added or removed on a title page or a tile reaches the page from the mirror — no
        // crawl. The title page is a cover above the shell, so its closing is the moment to look.
        .onChange(of: watchlistMarks?.lastOutcome?.event) { _, _ in Task { await model?.reloadCached() } }
        .onChange(of: router.detail == nil) { _, closed in
            if closed { Task { await model?.reloadCached() } }
        }
    }

    // MARK: - Building

    /// Builds (or, after Settings, rebuilds) the model. A model captures the settings it was built
    /// with — a username typed in Settings needs a new one to be read at all.
    private func build(force: Bool) {
#if DEBUG
        if let preview, preview.watchlistConnected != nil {
            connected = preview.watchlistConnected
            model = connected == true ? preview.watchlist : nil
            detailsStore = preview.watchlistDetails
            return
        }
#endif
        let username = UbiquitousLetterboxdSettingsStore().load().username
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let wasConnected = connected
        connected = !username.isEmpty
        guard connected == true else { model = nil; return }
        if model == nil || (force && wasConnected != true) {
            model = session.makeWatchlistModel()
            if force { Task { await model?.syncIfStale() } }
        }
        if detailsStore == nil { detailsStore = session.makeWatchlistDetailsStore() }
    }

#if DEBUG
    /// `-uiPreview watchlistremove|watchlistremoved|spin` — see `WatchlistPreviewScript`.
    private func runScript(_ script: WatchlistPreviewScript) async {
        await model?.refreshStatus()
        try? await Task.sleep(for: .seconds(5))
        guard let model else { return }
        if let slug = script.confirmRemovalOf {
            pendingRemoval = model.entries.first { $0.slug == slug }
        }
        if let slug = script.removeSlug, let entry = model.entries.first(where: { $0.slug == slug }) {
            await model.remove(entry)
        }
        if script.spins { spin = model.spin() }
    }
#endif

    private var countLine: String? {
        guard let model, !model.entries.isEmpty else { return nil }
        return WatchlistPageData.countLine(model.entries.count, partnerName: model.combinedStatus.partnerName)
    }

    // MARK: - Content

    @ViewBuilder private var content: some View {
        if connected == false {
            notConnected
        } else if let model {
            page(model)
        } else {
            // Only while the session is still assembling (the library store arrives with sign-in).
            ScrollView { RailSkeleton(rows: 3).padding(.top, Theme.Space.xxl) }
                .scrollDisabled(true)
        }
    }

    private func page(_ model: WatchlistModel) -> some View {
        let data = WatchlistPageData(model: model, details: detailsStore)
        let rows = data.rows
        let ids = model.entries.compactMap(\.tmdbID)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                status(model)
                if rows.isEmpty {
                    empty(model)
                } else {
                    if let first = rows.first?.entries.first {
                        featured(first, data: data)
                    }
                    ForEach(rows) { row in
                        rail(row, data: data)
                    }
                }
            }
            .padding(.top, Theme.Space.md)
            .padding(.bottom, Theme.Space.xxxl)
        }
        .refreshable { await model.syncNow() }
        // Every matched film's details — the rows that need them (rating, genre, runtime) appear
        // once a pass has settled. Store-owned, so leaving the page never cancels the fetch.
        .task(id: ids) { await detailsStore?.ensure(ids) }
        .task(id: rows.count) {
            ImageMemoryCache.prefetch(rows.prefix(3).flatMap { $0.entries.prefix(6) }.compactMap {
                TMDBClient.imageURL(path: $0.posterPath, size: "w342")
            })
        }
    }

    private func rail(_ row: WatchlistRow, data: WatchlistPageData) -> some View {
        let route = WatchlistGridRoute(rowID: row.id, title: row.title)
        let width = PosterTileMetrics.width(hSize)
        let shown = Array(row.entries.prefix(WatchlistRows.railLimit))
        return PosterRail(title: row.title, seeAll: route, subtitle: row.subtitle) {
            ForEach(shown) { entry in
                WatchlistFilmTile(entry: entry, owned: data.showsOwnedMark(entry, in: row.kind),
                                  badge: data.badge(for: entry), width: width,
                                  onRemove: { pendingRemoval = $0 })
            }
            // Every row has one, from the moment it exists — never a branch swap inside the row.
            NavigationLink(value: route) {
                SeeAllTile(title: row.title, width: width)
            }
            .pressable()
        }
        // One batched watched read per rail.
        .task(id: "\(row.id)/\(shown.count)") { await marks?.load(WatchlistFilmMarks.hits(shown)) }
    }

    // MARK: - Featured

    /// The first film of the first row, big: its backdrop (the poster until TMDB answers), its name
    /// and one line — "In Library · ready to play" for a film you can play now.
    private func featured(_ entry: WatchlistEntry, data: WatchlistPageData) -> some View {
        let item = MediaItem.watchlistTitle(entry, library: session.libraryStore)
        let backdrop = entry.tmdbID.flatMap { data.details[$0]?.backdropPath }
        let title = WatchlistName.stripYear(from: entry.name)
        let line = data.line(for: entry)
        let watched = WatchlistFilmMarks.isWatched(entry, item: item, session: session, marks: marks)
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return Button { if let item { router.detail = item } } label: {
            Color.clear
                .frame(height: featuredHeight)
                .overlay {
                    RemoteImage(url: TMDBClient.imageURL(path: backdrop ?? entry.posterPath,
                                                         size: backdrop == nil ? "w780" : "w1280")) {
                        Theme.Palette.surface1
                    }
                    .id(backdrop ?? entry.posterPath ?? entry.slug)
                }
                .overlay {
                    // Legibility for the name over any art.
                    LinearGradient(stops: [.init(color: .clear, location: 0.45),
                                           .init(color: Theme.Palette.shadeInk.opacity(0.85), location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.system(size: hSize == .regular ? 30 : 24, weight: .heavy))
                            .foregroundStyle(Theme.Palette.textPrimary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                        if !line.isEmpty {
                            Text(line)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Theme.Palette.textPrimary.opacity(0.82))
                                .lineLimit(1)
                        }
                    }
                    .shadow(color: .black.opacity(0.45), radius: 8, y: 1)
                    .padding(Theme.Space.lg)
                }
                .clipShape(shape)
                .overlay(shape.stroke(Theme.Palette.hairline, lineWidth: 0.5))
                .contentShape(shape)
        }
        .pressable()
        .contextMenu {
            WatchlistFilmActions(entry: entry, item: item, watched: watched,
                                 open: { if let item { router.detail = item } },
                                 onRemove: { pendingRemoval = $0 })
        }
        .accessibilityLabel(line.isEmpty ? title : "\(title), \(line)")
        .padding(.horizontal, PosterTileMetrics.margin(hSize))
    }

    /// 16:9 across an iPhone; capped on iPad, where the full width would fill the screen.
    private var featuredHeight: CGFloat { hSize == .regular ? 340 : 206 }

    // MARK: - States

    /// Sync progress and the problems worth a line: a crawl that failed over a list still shown, a
    /// removal that did not reach Letterboxd, a partner's list that could not be read.
    @ViewBuilder private func status(_ model: WatchlistModel) -> some View {
        let lines = statusLines(model)
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if line.busy {
                            ProgressView().controlSize(.small).tint(Theme.Palette.textSecondary)
                        } else if line.problem {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Theme.Palette.destructive)
                        }
                        Text(line.text)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(line.problem ? Theme.Palette.textPrimary : Theme.Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, Theme.Space.lg).padding(.vertical, Theme.Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .seretGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous), interactive: false)
            .padding(.horizontal, PosterTileMetrics.margin(hSize))
        }
    }

    private struct StatusLine { let text: String; var busy = false; var problem = false }

    private func statusLines(_ model: WatchlistModel) -> [StatusLine] {
        var lines: [StatusLine] = []
        switch model.phase {
        case .syncing(let done, let total):
            // With nothing on the page yet, the empty state says this instead.
            if !model.entries.isEmpty {
                lines.append(StatusLine(text: total > 0 ? "Matching \(done) of \(total)…"
                                                        : "Reading your watchlist…", busy: true))
            }
        case .failed(let message):
            if !model.entries.isEmpty { lines.append(StatusLine(text: message, problem: true)) }
        case .idle:
            break
        }
        if let message = model.relayMessage { lines.append(StatusLine(text: message, problem: true)) }
        // Secondary, not red: the owner's own list is fine and nothing they asked for failed.
        if let message = model.partnerMessage { lines.append(StatusLine(text: message)) }
        return lines
    }

    @ViewBuilder private func empty(_ model: WatchlistModel) -> some View {
        switch model.phase {
        case .syncing(let done, let total):
            VStack(spacing: Theme.Space.md) {
                ProgressView().tint(Theme.Palette.focus)
                Text(total > 0 ? "Matching \(done) of \(total)…" : "Reading your watchlist…")
                    .font(Theme.Typo.body())
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 100)
        case .failed(let message):
            WatchlistMessageCard(systemImage: "exclamationmark.triangle",
                                 title: "Couldn't read your watchlist", text: message) {
                PrimaryPill(title: "Try Again", systemImage: "arrow.clockwise") {
                    Task { await model.syncNow() }
                }
            }
        case .idle:
            WatchlistMessageCard(systemImage: "bookmark", title: "Nothing on your watchlist yet",
                                 text: "Films you add on Letterboxd, or with the bookmark on a title, show up here.") {
                GlassPill(title: "Sync Now", systemImage: "arrow.triangle.2.circlepath") {
                    Task { await model.syncNow() }
                }
            }
        }
    }

    /// Letterboxd isn't set up: say so, and go straight to where it is.
    private var notConnected: some View {
        ScrollView {
            WatchlistMessageCard(systemImage: "person.crop.circle.badge.questionmark",
                                 title: "Connect Letterboxd",
                                 text: "Your watchlist comes from your Letterboxd profile. Add your username in Settings to see it here.") {
                PrimaryPill(title: "Open Settings", systemImage: "gearshape") { showingSettings = true }
            }
        }
    }
}

/// A centred glass card for a page with nothing to list: an icon, a title, a sentence, an action.
struct WatchlistMessageCard<Action: View>: View {
    let systemImage: String
    let title: String
    let text: String
    @ViewBuilder var action: Action
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        VStack(spacing: Theme.Space.md) {
            Image(systemName: systemImage)
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(Theme.Palette.textSecondary)
            Text(title)
                .font(Theme.Typo.title())
                .foregroundStyle(Theme.Palette.textPrimary)
                .multilineTextAlignment(.center)
            Text(text)
                .font(Theme.Typo.body())
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            action.padding(.top, Theme.Space.sm)
        }
        .padding(Theme.Space.xxl)
        .frame(maxWidth: 440)
        .seretGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous), interactive: false)
        .padding(.horizontal, PosterTileMetrics.margin(hSize))
        .padding(.top, 60)
        .frame(maxWidth: .infinity)
    }
}
