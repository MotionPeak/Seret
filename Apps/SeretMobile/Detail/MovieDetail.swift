import DebridCore
import DebridUI
import SwiftUI

/// Movie Detail: backdrop, title + meta, quality chips, Play/Resume, overview, and Versions.
struct MovieDetail: View {
    let store: DetailStore
    let onPlay: (PlaybackRequest) -> Void
    /// Per-version remove (one MediaSource → one RD torrent). Owner-injected; nil hides the
    /// affordance.
    var onRemoveVersion: ((MediaSource) -> Void)? = nil
    /// A "More Like This" poster was tapped — owned opens its Detail, new opens the Add flow.
    /// The parent presents (see `SimilarRail`).
    var onOpenTitle: (MediaItem) -> Void = { _ in }
    var onAddTitle: (SearchHit) -> Void = { _ in }
    private var item: MediaItem { store.item }
    private var contentKey: String { WatchKey.content(forMovie: item) }
    private var watch: WatchState? { store.watchState(forKey: contentKey) }
    private var isWatched: Bool { watch?.finished == true }
    @State private var pendingVersionRemoval: MediaSource?
    /// Drives Play on a title that is not in the library: find the best cached release, add it, play.
    @State private var acquisition: AcquisitionStore?
    @Environment(AppSession.self) private var session

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                TrailerHero(tmdbID: item.tmdbID, kind: .movie,
                            backdropPath: store.backdropPath, posterFallback: item.posterPath)
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                Text(item.title).font(Theme.Typo.titleXL()).foregroundStyle(Theme.Palette.textPrimary)
                Text(metaLine).font(Theme.Typo.body()).foregroundStyle(Theme.Palette.textSecondary)
                if !store.directors.isEmpty {
                    CreditNamesRow(label: store.directors.count == 1 ? "Dir." : "Dirs.",
                                   people: store.directors)
                }
                if let franchise = store.franchise {
                    Text("Film \(franchise.position) of \(franchise.count)  ·  \(franchise.name)")
                        .font(Theme.Typo.body()).foregroundStyle(Theme.Palette.gold)
                }
                if let best = store.bestSource { QualityChipRow(parsed: best.parsed) }
                RatingsRow(ratings: store.ratings, community: store.communityScore)
                actions
                UserRatingRow(store: store)
                WatchDatesLine(summary: store.watchSummary, since: store.historySince)
                    .task { await store.loadWatchSummary() }
                    .task { await store.loadPreferredVersion() }
                    // Rebuilt when the imdbID resolves — the engine cannot query without it.
                    .task(id: store.imdbID) {
                        acquisition = session.makeAcquisition(for: store.item, imdbID: store.imdbID,
                                                              originalLanguage: store.originalLanguage)
                    }
                if case let .failed(message) = acquisition?.phase {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(Theme.Typo.caption()).foregroundStyle(.orange)
                }
                if let tmdb = item.tmdbID,
                   store.bestSource == nil
                    || session.downloadStore?
                        .status(forContentKey: DownloadKey.movie(tmdbID: tmdb)) != nil {
                    MovieDownloadSection(tmdbID: tmdb, title: item.title, posterPath: item.posterPath,
                                         imdbID: store.imdbID, originalLanguage: store.originalLanguage)
                }
                if let overview = store.overview {
                    Text(overview).font(Theme.Typo.body())
                        .foregroundStyle(Theme.Palette.textSecondary).lineSpacing(3)
                }
                versionsSection
                // Franchise sits above cast: which film in the series this is matters more than
                // who is in it.
                if let franchise = store.franchise {
                    FranchiseRail(franchise: franchise, currentTmdbID: item.tmdbID,
                                  onOpen: onOpenTitle)
                }
                // Gated on non-empty: the rails only appear once TMDB credits land, and they append
                // BELOW everything else, so they never resize content already on screen.
                if !store.cast.isEmpty { CastRail(cast: store.cast) }
                if !store.similar.isEmpty {
                    SimilarRail(titles: store.similar, parentKind: .movie,
                                onOpenOwned: onOpenTitle, onAddNew: onAddTitle)
                }
            }
            .frame(maxWidth: 700, alignment: .leading)
            .padding(.horizontal, Theme.Space.lg)
            .padding(.top, Theme.Space.lg)
            .padding(.bottom, Theme.Space.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(CanvasBackground())
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: acquisition?.phase) { _, phase in
            guard case let .ready(request) = phase else { return }
            session.libraryStore?.retry()      // a new torrent landed in RD
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

    private var metaLine: String {
        var parts: [String] = []
        if let y = item.year { parts.append(String(y)) }
        if let r = store.runtime { parts.append("\(r) min") }
        if !store.genres.isEmpty { parts.append(store.genres.prefix(3).joined(separator: " · ")) }
        // The director is NOT folded in here any more — it is its own row of tappable names.
        return parts.joined(separator: "  ·  ")
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: Theme.Space.md) {
            if let best = store.bestSource {
                if let resume = resumeSeconds {
                    Button { onPlay(store.playRequest(source: best, episode: nil, label: item.title)) } label: {
                        Label("Resume · \(Timecode.format(resume))", systemImage: "play.fill")
                    }.buttonStyle(GoldButtonStyle())
                    Button { onPlay(store.playRequest(source: best, episode: nil, label: item.title, fromStart: true)) } label: {
                        Label("Start", systemImage: "gobackward")
                    }.buttonStyle(GhostButtonStyle())
                } else {
                    Button { onPlay(store.playRequest(source: best, episode: nil, label: item.title)) } label: {
                        Label("Play", systemImage: "play.fill")
                    }.buttonStyle(GoldButtonStyle())
                }
            } else {
                // Not in the library: Play still means play. It finds the best instantly-available
                // release, adds it, and starts.
                Button { Task { await acquisition?.playBest(.movie) } } label: {
                    Label(acquiringLabel, systemImage: acquiring ? "hourglass" : "play.fill")
                }
                .buttonStyle(GoldButtonStyle())
                .disabled(acquiring || acquisition == nil)
            }
            Spacer(minLength: 0)
            watchedMenu()
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

    /// A trailing "…" menu holding Mark Watched/Unwatched — off the primary Play path (mirrors the
    /// tvOS Detail's More menu). Available whether or not you own the title: a title you have not
    /// added is marked by content key alone.
    private func watchedMenu() -> some View {
        Menu {
            Button {
                Task { await store.setWatched(!isWatched, contentKey: contentKey,
                                              source: store.bestSource) }
            } label: {
                Label(isWatched ? "Mark Unwatched" : "Mark Watched",
                      systemImage: isWatched ? "checkmark.circle.fill" : "checkmark.circle")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title2).foregroundStyle(Theme.Palette.gold)
                .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
        }
        .accessibilityLabel("More options")
    }

    /// The Add flow for this title — it already hosts the full cached/uncached versions browser,
    /// so Detail routes there rather than growing a second one. Needs a TMDB id to search.
    private var otherVersionsHit: SearchHit? {
        guard let tmdb = item.tmdbID else { return nil }
        return SearchHit(result: TMDBSearchResult(
            id: tmdb, title: item.title, name: nil, releaseDate: nil, firstAirDate: nil,
            posterPath: item.posterPath, overview: nil, voteAverage: nil), kind: .movie)
    }

    private var versionsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack {
                // On a title you do not own there is nothing to list yet — the section becomes the
                // way to GET one, so it stays on the page either way.
                Text(store.versions.isEmpty ? "GET THIS TITLE" : "VERSIONS")
                    .font(Theme.Typo.label()).tracking(1.5)
                    .foregroundStyle(Theme.Palette.gold)
                Spacer()
                if let hit = otherVersionsHit {
                    Button { onAddTitle(hit) } label: {
                        Label(store.versions.isEmpty ? "Versions" : "Find Other",
                              systemImage: "square.stack.3d.up")
                            .font(Theme.Typo.caption())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.Palette.gold)
                }
            }
            ForEach(store.versions, id: \.self) { src in versionRow(src) }
        }
    }

    private func versionRow(_ src: MediaSource) -> some View {
        HStack {
            Button { onPlay(store.playRequest(source: src, episode: nil, label: item.title)) } label: {
                HStack {
                    Image(systemName: store.isActive(src) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(store.isActive(src)
                                         ? Theme.Palette.gold : Theme.Palette.textSecondary)
                    QualityChipRow(parsed: src.parsed)
                    Spacer()
                    Image(systemName: "play.circle.fill").foregroundStyle(Theme.Palette.gold)
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
                        .padding(.leading, Theme.Space.sm)
                        .frame(minWidth: 30, minHeight: 30)
                        .contentShape(Rectangle())
                }
            .menuStyle(.borderlessButton)
        }
        .padding(Theme.Space.md)
        .background(Theme.Palette.surface2, in: RoundedRectangle(cornerRadius: Theme.Radius.chip))
    }

    private var resumeSeconds: Double? {
        guard let w = watch, !w.finished, w.positionSeconds > 0 else { return nil }
        return w.positionSeconds
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

    var body: some View {
        let status = session.downloadStore?.status(forContentKey: DownloadKey.movie(tmdbID: tmdbID))
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            if requesting && status == nil {
                ProgressView("Starting download…").tint(Theme.Palette.gold)
            } else if case .queued = status?.phase {
                ProgressView("Starting download…").tint(Theme.Palette.gold)
            } else if case .downloading = status?.phase {
                let pct = Int((status?.fraction ?? 0) * 100)
                Label("Downloading \(pct)% to Real‑Debrid…", systemImage: "arrow.down.circle.fill")
                    .font(Theme.Typo.body()).foregroundStyle(Theme.Palette.gold)
                ProgressView(value: status?.fraction ?? 0).tint(Theme.Palette.gold)
                Text("It'll appear here when it's ready.")
                    .font(Theme.Typo.caption()).foregroundStyle(Theme.Palette.textTertiary)
            } else if case .failed(let reason) = status?.phase {
                Label(reason, systemImage: "exclamationmark.triangle")
                    .font(Theme.Typo.body()).foregroundStyle(.orange)
                requestButton("Try Another Version")
            } else {
                Label("Not in your library yet", systemImage: "arrow.down.circle")
                    .font(Theme.Typo.body()).foregroundStyle(Theme.Palette.textSecondary)
                Text("No cached version exists. Start a download and it'll appear here when it's ready.")
                    .font(Theme.Typo.caption()).foregroundStyle(Theme.Palette.textTertiary)
                requestButton("Request Download")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func requestButton(_ label: String) -> some View {
        Button {
            Task {
                requesting = true
                var candidates: [CachedStream] = []
                if let imdbID, let add = session.makeAddStore(imdbID: imdbID, kind: .movie,
                                                              originalLanguage: originalLanguage) {
                    candidates = await add.uncachedCandidates()
                }
                await session.downloadStore?.request(contentKey: DownloadKey.movie(tmdbID: tmdbID),
                                                     tmdbID: tmdbID, title: title, kind: .movie,
                                                     candidates: candidates, posterPath: posterPath)
                requesting = false
            }
        } label: { Label(label, systemImage: "arrow.down.circle") }
            .buttonStyle(GoldButtonStyle())
            .disabled(requesting || imdbID == nil)
    }
}
