import DebridCore
import DebridUI
import SwiftUI

/// Movie title page (g3): full-bleed art under the glass bar, logo, metadata, chips, a full-width
/// white Play / Resume, the labelled glass circles (Trailer · Watchlist · Watched · Versions ·
/// More), the overview, then ratings, your rating, the download section, versions and the rails.
struct MovieDetail: View {
    let store: DetailStore
    /// Set as the page scrolls past the hero — the bar takes the title then (see DetailScreen).
    @Binding var heroScrolled: TitleScroll
    let onPlay: (PlaybackRequest) -> Void
    /// Per-version remove (one MediaSource → one RD torrent). Owner-injected; nil hides the
    /// affordance.
    var onRemoveVersion: ((MediaSource) -> Void)? = nil
    /// A "More Like This" poster was tapped — owned opens its Detail, new opens the Add flow.
    /// The parent presents (see `SimilarRail`).
    var onOpenTitle: (MediaItem) -> Void = { _ in }
    var onAddTitle: (SearchHit) -> Void = { _ in }
    /// "Remove from Library" — the parent confirms and performs it.
    var onRemoveTitle: () -> Void = {}
    private var item: MediaItem { store.item }
    private var contentKey: String { WatchKey.content(forMovie: item) }
    private var watch: WatchState? { store.watchState(forKey: contentKey) }
    private var isWatched: Bool { watch?.finished == true }
    @State private var pendingVersionRemoval: MediaSource?
    /// Drives Play on a title that is not in the library: find the best cached release, add it, play.
    @State private var acquisition: AcquisitionStore?
    @Environment(AppSession.self) private var session
    @Environment(\.horizontalSizeClass) private var hSize
    /// Absent until `DetailScreen` has built it, and absent in previews — the control is then
    /// simply not offered, which beats offering one that does nothing.
    @Environment(WatchlistMarks.self) private var watchlist: WatchlistMarks?

    private var regular: Bool { hSize == .regular }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                TitleHero(tmdbID: item.tmdbID, kind: .movie, backdropPath: store.backdropPath,
                          posterFallback: item.posterPath, regular: regular) {
                    heroInfo
                } buttons: { trailer in
                    heroButtons(trailer)
                }
                sections
                    .titleColumn(regular: regular)
                    .padding(.top, regular ? Theme.Space.xxxl : Theme.Space.xxl)
                rails
                    .padding(.top, Theme.Space.xxxl)
                    .padding(.bottom, 48)
            }
        }
        // The art runs up under the status bar and the glass bar, as g3 draws it.
        .ignoresSafeArea(edges: .top)
        .titlePageScroll($heroScrolled)
        // On the ScrollView, not on WatchDatesLine. That view renders NOTHING until the summary it
        // is waiting for arrives, and hanging the load that produces it — plus the version lookup
        // and the acquisition engine — off a view with a conditionally-empty body makes all three
        // depend on SwiftUI choosing to keep an empty view in the tree.
        .task { await store.loadWatchSummary() }
        .task { await store.loadPreferredVersion() }
        // Rebuilt when the imdbID resolves — the engine cannot query without it.
        .task(id: store.imdbID) {
            acquisition = session.makeAcquisition(for: store.item, imdbID: store.imdbID,
                                                  originalLanguage: store.originalLanguage,
                                                  runtimeMinutes: store.runtime)
        }
        .background(CanvasBackground())
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu { moreItems } label: { ToolbarGlassIcon(systemImage: "ellipsis") }
                    .tint(Theme.Palette.focus)
                    .accessibilityLabel("More")
            }
        }
        .onChange(of: acquisition?.phase) { _, phase in
            guard case let .ready(request) = phase else { return }
            session.libraryStore?.reload()     // a new torrent landed in RD
            acquisition?.reset()
            onPlay(request)
        }
        .confirmationDialog(
            "Remove this version?",
            isPresented: Binding(get: { pendingVersionRemoval != nil },
                                 set: { if !$0 { pendingVersionRemoval = nil } }),
            titleVisibility: .visible,
            presenting: pendingVersionRemoval) { src in
                Button("Remove", role: .destructive) {
                    if let onRemoveVersion { onRemoveVersion(src) }
                    pendingVersionRemoval = nil
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("This deletes just this version from your Real\u{2011}Debrid account.")
            }
    }

    // MARK: Hero

    private var heroInfo: some View {
        VStack(alignment: .leading, spacing: 12) {
            TitleLogo(title: item.title, logoPath: store.logoPath,
                      settling: store.richState == .idle || store.richState == .loading,
                      maxWidth: regular ? 440 : 320, maxHeight: regular ? 130 : 104,
                      alignment: .bottomLeading,
                      font: .system(size: regular ? 48 : 38, weight: .heavy))
            TitleMetaRow(parts: metaParts)
            chips
        }
    }

    /// Year, runtime, ★ TMDB score, genres, then the original language.
    private var metaParts: [String] {
        var parts: [String] = []
        if let y = item.year { parts.append(String(y)) }
        if let r = store.runtime, r > 0 { parts.append(TitleMetaRow.duration(minutes: r)) }
        if let star = TitleMetaRow.rating(store.voteAverage) { parts.append(star) }
        if !store.genres.isEmpty { parts.append(store.genres.prefix(2).joined(separator: " · ")) }
        if let language = store.languageName { parts.append(language) }
        return parts
    }

    /// The best version's quality and the title's Hebrew mark (g3: 2160p · HDR · Atmos · Hebrew).
    @ViewBuilder private var chips: some View {
        let quality = store.bestSource.map { best in
            [best.parsed.resolution, best.parsed.source, best.parsed.videoCodec, best.parsed.audioCodec]
                .compactMap { $0 }
        } ?? []
        if !quality.isEmpty || store.hebrewChip != nil {
            FlowLayout(spacing: Theme.Space.sm) {
                ForEach(quality, id: \.self) { OutlineChip(text: $0) }
                if let chip = store.hebrewChip {
                    HebrewBadge(HebrewIndicator(chip: chip), prominent: true)
                }
            }
        }
    }

    private func heroButtons(_ trailer: TrailerAction) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            playButton
                .frame(maxWidth: regular ? 380 : .infinity)
            if case let .failed(message) = acquisition?.phase {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(Theme.Typo.caption()).foregroundStyle(Theme.Palette.textSecondary)
            }
            TitleActionRow(regular: regular) {
                GlassActionButton(systemImage: "play.rectangle", title: "Trailer",
                                  accessibility: "Play Trailer", action: trailer.play)
                    .disabled(!trailer.isAvailable)
                watchlistAction
                GlassActionButton(systemImage: "checkmark", title: "Watched", isOn: isWatched,
                                  accessibility: isWatched ? "Mark Unwatched" : "Mark Watched") {
                    Task { await store.setWatched(!isWatched, contentKey: contentKey,
                                                  source: store.bestSource) }
                }
                if let hit = otherVersionsHit {
                    GlassActionButton(systemImage: "square.stack.3d.up", title: "Versions",
                                      accessibility: "All Versions") { onAddTitle(hit) }
                }
                Menu { moreItems } label: {
                    GlassActionLabel(systemImage: "ellipsis", title: "More")
                }
                .buttonStyle(GlassPressStyle())
                .accessibilityLabel("More")
            }
        }
    }

    /// Play / Resume, full width. Not in the library: Play still means play — it finds the best
    /// instantly-available release, adds it, and starts.
    @ViewBuilder private var playButton: some View {
        if let best = store.bestSource {
            Button { onPlay(store.playRequest(source: best, episode: nil, label: item.title)) } label: {
                Label(resumeSeconds.map { "Resume · \(Timecode.format($0))" } ?? "Play",
                      systemImage: "play.fill")
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .buttonStyle(PrimaryPillButtonStyle(fullWidth: true))
        } else {
            Button { Task { await acquisition?.playBest(.movie) } } label: {
                Label(acquiringLabel, systemImage: acquiring ? "hourglass" : "play.fill")
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .buttonStyle(PrimaryPillButtonStyle(fullWidth: true))
            // …and until the IMDb id has resolved. The engine cannot query an indexer without it, so
            // tapping earlier failed with "Not signed in to Real-Debrid" — a reason that is not
            // only unhelpful but untrue.
            .disabled(acquiring || acquisition == nil || store.imdbID == nil)
        }
    }

    /// Films only — Letterboxd has no watchlist a show can go on. Its own circle rather than a line
    /// in More: it is the one thing you do to a film you have NOT watched, which is most of what
    /// reaches an unowned title.
    @ViewBuilder private var watchlistAction: some View {
        if let film = WatchlistFilm(item: item), let watchlist {
            let on = watchlist.contains(tmdbID: film.tmdbID)
            GlassActionButton(systemImage: on ? "bookmark.fill" : "bookmark", title: "Watchlist",
                              isOn: on,
                              accessibility: on ? "Remove from Watchlist" : "Add to Watchlist") {
                Task { await watchlist.toggle(film: film) }
            }
            .disabled(watchlist.isInFlight(tmdbID: film.tmdbID))
        }
    }

    /// The More menu — the same items from the action row's circle and the bar's ⋯.
    @ViewBuilder private var moreItems: some View {
        if let best = store.bestSource, resumeSeconds != nil {
            Button("Play from Beginning", systemImage: "gobackward") {
                onPlay(store.playRequest(source: best, episode: nil, label: item.title, fromStart: true))
            }
        }
        Button(store.inMyList ? "In My List" : "Add to My List",
               systemImage: store.inMyList ? "checkmark" : "plus") {
            Task { await store.toggleMyList(contentKey: store.item.id) }
        }
        if store.preferredSourceKey != nil {
            Button("Use Best Version Automatically", systemImage: "wand.and.stars") {
                Task { await store.clearPreferredVersion() }
            }
        }
        // Only for a title that has files. On a source-less page (a Watchlist entry, a title not
        // yet added) there is nothing to delete from Real-Debrid — and "removing" it hid the real
        // library title from Seret for good and wiped its history.
        if store.isInLibrary {
            Divider()
            Button("Remove from Library", systemImage: "trash", role: .destructive, action: onRemoveTitle)
        }
    }

    /// True while a release is being found or added.
    private var acquiring: Bool {
        switch acquisition?.phase {
        case .finding, .adding: true
        default: false
        }
    }

    private var acquiringLabel: String {
        switch acquisition?.phase {
        case .finding: "Finding…"
        case .adding: "Starting…"
        default: "Play"
        }
    }

    // MARK: Sections

    private var sections: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxxl) {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                if let overview = store.overview, !overview.isEmpty {
                    ExpandableOverview(text: overview)
                }
                if !store.directors.isEmpty {
                    CreditNamesRow(label: store.directors.count == 1 ? "Director" : "Directors",
                                   people: store.directors)
                }
                if let franchise = store.franchise {
                    Text("Film \(franchise.position) of \(franchise.count)  ·  \(franchise.name)")
                        .font(Theme.Typo.body()).foregroundStyle(Theme.Palette.textSecondary)
                }
                RatingsRow(ratings: store.ratings, letterboxd: store.letterboxdRating)
                WatchDatesLine(summary: store.watchSummary, since: store.historySince)
            }
            UserRatingRow(store: store)
            if let tmdb = item.tmdbID, showsDownloadSection(tmdbID: tmdb) {
                MovieDownloadSection(tmdbID: tmdb, title: item.title, posterPath: item.posterPath,
                                     imdbID: store.imdbID, originalLanguage: store.originalLanguage)
            }
            versionsSection
        }
    }

    /// The rails run the page's full width (they scroll to the edge), starting on the page margin.
    private var rails: some View {
        let margin = TitlePageMetrics.margin(regular: regular)
        return VStack(alignment: .leading, spacing: Theme.Space.xxxl) {
            // Franchise sits above cast: which film in the series this is matters more than who
            // is in it.
            if let franchise = store.franchise {
                FranchiseRail(franchise: franchise, currentTmdbID: item.tmdbID,
                              onOpen: onOpenTitle, margin: margin)
            }
            // Gated on non-empty: the rails only appear once TMDB credits land, and they append
            // BELOW everything else, so they never resize content already on screen.
            if !store.cast.isEmpty { CastRail(cast: store.cast, margin: margin) }
            if !store.similar.isEmpty {
                SimilarRail(titles: store.similar, parentKind: .movie,
                            onOpen: onOpenTitle, margin: margin)
            }
        }
    }

    /// The Add flow for this title — it already hosts the full cached/uncached versions browser,
    /// so Detail routes there rather than growing a second one. Needs a TMDB id to search.
    private var otherVersionsHit: SearchHit? {
        guard let tmdb = item.tmdbID else { return nil }
        return SearchHit(result: TMDBSearchResult(
            id: tmdb, title: item.title, name: nil, releaseDate: nil, firstAirDate: nil,
            posterPath: item.posterPath, overview: nil, voteAverage: nil), kind: .movie)
    }

    @ViewBuilder private var versionsSection: some View {
        // On a title you do not own there is nothing to list — the Versions circle is the way to
        // GET one, so the section only appears once there is something of yours to show.
        if !store.versions.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                TitleSectionHeader(title: store.versions.count == 1 ? "Your Version" : "Your Versions") {
                    if let hit = otherVersionsHit {
                        Button { onAddTitle(hit) } label: {
                            Label("Find Other", systemImage: "square.stack.3d.up")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.Palette.textSecondary)
                    }
                }
                ForEach(store.versions, id: \.self) { src in versionRow(src) }
            }
        }
    }

    private func versionRow(_ src: MediaSource) -> some View {
        HStack {
            Button { onPlay(store.playRequest(source: src, episode: nil, label: item.title)) } label: {
                HStack(spacing: Theme.Space.md) {
                    Image(systemName: store.isActive(src) ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundStyle(store.isActive(src)
                                         ? Theme.Palette.focus : Theme.Palette.textTertiary)
                        .accessibilityLabel(store.isActive(src) ? "Plays by default" : "")
                    // The marks on lines of their own: an iPhone row has no room beside four
                    // chips, and this is the one fact about a version that must never be truncated
                    // away. Hebrew inside the file is always in sync, so it goes on top, as in the
                    // Versions list.
                    VStack(alignment: .leading, spacing: 5) {
                        let hebrew = HebrewIndicator(store.hebrew(for: src))
                        if hebrew == .inFile { HebrewBadge(.inFile) }
                        QualityChipRow(parsed: src.parsed)
                        if hebrew == .matched { HebrewBadge(.matched) }
                        if let bytes = src.sizeBytes {
                            Text(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
                                .font(Theme.Typo.caption()).foregroundStyle(Theme.Palette.textTertiary)
                        }
                    }
                    Spacer()
                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(Theme.Palette.glass, in: Circle())
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Menu {
                if !store.isActive(src) {
                    Button("Make Default", systemImage: "checkmark.circle") {
                        Task { await store.chooseVersion(src) }
                    }
                }
                if store.preferredSourceKey != nil {
                    Button("Use Best Automatically", systemImage: "wand.and.stars") {
                        Task { await store.clearPreferredVersion() }
                    }
                }
                if onRemoveVersion != nil {
                    Button("Remove this version", systemImage: "trash", role: .destructive) {
                        pendingVersionRemoval = src
                    }
                }
            } label: {
                Image(systemName: "ellipsis").foregroundStyle(Theme.Palette.textSecondary)
                    .frame(minWidth: 36, minHeight: 36)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("Version Options")
        }
        .padding(Theme.Space.md)
        .background(Theme.Palette.glassFaint,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            .strokeBorder(Theme.Palette.hairline))
    }

    private var resumeSeconds: Double? {
        return watch?.resumePosition
    }

    /// The download section shows once there is a reason for it: Play looked and found nothing it
    /// could start, or a download of this film already exists. It used to sit on every film you
    /// don't own, announcing "No cached version exists" before anything had been checked — even
    /// on films with Instant versions, where Play would have started at once. (Ported from the
    /// tvOS `offersDownload`.)
    ///
    /// Owned is asked of the LIBRARY as well as the page: the library lists a finished download a
    /// moment before the page adopts it, and for that moment the page alone offered "Request
    /// Download" again. A finished download on an owned film shows nothing — Play is right there.
    private func showsDownloadSection(tmdbID: Int) -> Bool {
        let owned = store.bestSource != nil
            || session.libraryStore?.ownedItem(tmdbID: tmdbID, kind: .movie) != nil
        if let status = session.downloadStore?.status(forContentKey: DownloadKey.movie(tmdbID: tmdbID)) {
            if case .ready = status.phase { return !owned }
            return true
        }
        guard !owned else { return false }
        switch acquisition?.phase {
        case .noneCached, .failed: return true
        default: return false
        }
    }
}

/// Request Download for a movie with no cached/playable version — the Detail-screen sibling of the
/// Add flow's section. Fetches the best uncached release via the shared Add seam and starts an RD
/// download, then shows live progress from the app-wide `DownloadStore`. When it finishes, the
/// title flips into the library and Play lights up.
private struct MovieDownloadSection: View {
    let tmdbID: Int
    let title: String
    let posterPath: String?
    let imdbID: String?
    let originalLanguage: String?
    @Environment(AppSession.self) private var session
    @State private var requesting = false
    @State private var showingMagnet = false

    var body: some View {
        let status = session.downloadStore?.status(forContentKey: DownloadKey.movie(tmdbID: tmdbID))
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            if requesting && status == nil {
                ProgressView("Starting download…").tint(Theme.Palette.focus)
            } else if case .queued = status?.phase {
                ProgressView("Starting download…").tint(Theme.Palette.focus)
            } else if case .downloading = status?.phase {
                let pct = Int((status?.fraction ?? 0) * 100)
                Label("Downloading \(pct)% to Real‑Debrid…", systemImage: "arrow.down.circle.fill")
                    .font(Theme.Typo.body()).foregroundStyle(Theme.Palette.textPrimary)
                ProgressView(value: status?.fraction ?? 0).tint(Theme.Palette.focus)
                Text("It'll appear here when it's ready.")
                    .font(Theme.Typo.caption()).foregroundStyle(Theme.Palette.textTertiary)
            } else if case .failed(let reason) = status?.phase {
                Label(reason, systemImage: "exclamationmark.triangle")
                    .font(Theme.Typo.body()).foregroundStyle(.orange)
                requestButton("Try Another Version")
                magnetButton
            } else if case .ready = status?.phase {
                // Finished. Not "Request Download": that was what this said in the seconds before
                // the library caught up, and pressing it started a second torrent.
                Label("Downloaded \u{2014} it\u{2019}s in your library.", systemImage: "checkmark.circle.fill")
                    .font(Theme.Typo.body()).foregroundStyle(Theme.Palette.textPrimary)
            } else {
                Label("Not in your library yet", systemImage: "arrow.down.circle")
                    .font(Theme.Typo.body()).foregroundStyle(Theme.Palette.textSecondary)
                Text("No cached version exists. Start a download and it'll appear here when it's ready.")
                    .font(Theme.Typo.caption()).foregroundStyle(Theme.Palette.textTertiary)
                requestButton("Request Download")
                magnetButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $showingMagnet) {
            MagnetAddSheet(target: .init(contentKey: DownloadKey.movie(tmdbID: tmdbID),
                                         tmdbID: tmdbID, title: title,
                                         kind: .movie, posterPath: posterPath))
                .environment(session)
        }
    }

    /// The escape hatch for a title no indexer carries — old Israeli TV, anything off the public
    /// trackers. Paste the magnet and RD downloads it under this title's key.
    private var magnetButton: some View {
        Button { showingMagnet = true } label: {
            Label("Add by Magnet", systemImage: "link.badge.plus")
        }
        .buttonStyle(GlassPillButtonStyle())
    }

    private func requestButton(_ label: String) -> some View {
        Button {
            Task {
                requesting = true
                var candidates: [CachedStream] = []
                if let imdbID, let add = session.makeAddStore(imdbID: imdbID, kind: .movie,
                                                              originalLanguage: originalLanguage,
                                                              subtitleTarget: .movie(tmdbID: tmdbID, title: title,
                                                                                     year: nil)) {
                    candidates = await add.uncachedCandidates()
                }
                await session.downloadStore?.request(contentKey: DownloadKey.movie(tmdbID: tmdbID),
                                                     tmdbID: tmdbID, title: title, kind: .movie,
                                                     candidates: candidates, posterPath: posterPath)
                requesting = false
            }
        } label: { Label(label, systemImage: "arrow.down.circle") }
            .buttonStyle(PrimaryPillButtonStyle())
            .disabled(requesting || imdbID == nil)
    }
}
