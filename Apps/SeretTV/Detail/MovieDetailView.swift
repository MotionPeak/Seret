import DebridCore
import DebridUI
import SwiftUI

/// Movie Detail: backdrop hero, metadata, overview, Play/Resume, Versions, Mark Watched.
struct MovieDetailView: View {
    let store: DetailStore
    var onRemove: () -> Void = {}
    /// One version was chosen for deletion — the host confirms, then deletes it from Real-Debrid.
    var onRemoveVersion: (MediaSource) -> Void = { _ in }

    private var item: MediaItem { store.item }
    private var contentKey: String { WatchKey.content(forMovie: item) }
    private var watch: WatchState? { store.watchState(forKey: contentKey) }
    @State private var trailerURL: URL?
    @State private var expandTrailer = false
    /// Forces INITIAL focus onto the Play CTA. Without it the action row sits below the tall hero
    /// (off-screen on open) and tvOS sets no initial focus — the remote goes dead. `.defaultFocus`
    /// puts focus on Play and scrolls it into view.
    private enum Field: Hashable { case play }
    @FocusState private var initialFocus: Field?
    @Environment(AppSession.self) private var session
    /// Absent until `DetailView` has built it, and absent in previews — the button is simply not
    /// offered then, which beats offering one that does nothing.
    @Environment(WatchlistMarks.self) private var watchlist: WatchlistMarks?
    /// Drives Play on a title that is not in the library: find the best cached release, add it, play.
    @State private var acquisition: AcquisitionStore?
    /// Why Play cannot search, said once it is pressed — see the unowned Play button.
    @State private var playUnavailable: String?
    /// On screen right now. A play that resolves after the viewer has left — Menu pressed while
    /// "Finding a version…" was still searching — must not push the player over whatever page they
    /// went to (or over a film already playing, which the push then tore down).
    @State private var isOnScreen = false
    /// Opens the player as a PUSH. A full-screen cover cannot host it on tvOS: inside a cover the
    /// Menu press never reaches the player's own handler — the cover dismisses itself first — so
    /// Menu with Settings or the subtitle list open walked out of the film instead of closing the
    /// panel, and Menu could not abandon a scrub or a scan either. Pushed, it behaves like every
    /// other play path.
    @Environment(\.openBrowseDestination) private var openDestination

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                TrailerHero(tmdbID: item.tmdbID, kind: .movie,
                            backdropPath: store.backdropPath, posterFallback: item.posterPath,
                            resolvedURL: $trailerURL, paused: expandTrailer)
                VStack(alignment: .leading, spacing: 36) {
                    hero.frame(maxWidth: .infinity, alignment: .leading)
                    if !store.versions.isEmpty { versionsSection }
                    // Franchise sits above cast: which film in the series this is matters more
                    // than who is in it. Appends below the hero, so it never resizes what is
                    // already on screen.
                    if let franchise = store.franchise {
                        FranchiseRail(franchise: franchise, currentTmdbID: item.tmdbID)
                    }
                    // Gated on non-empty: the rail only ever appears once TMDB credits land, and it
                    // appends BELOW everything else, so it never resizes content already on screen.
                    if !store.cast.isEmpty { CastRail(cast: store.cast) }
                    if !store.similar.isEmpty {
                        SimilarRail(titles: store.similar, parentKind: .movie)
                    }
                }
                .padding(60)
            }
        }
        .defaultFocus($initialFocus, .play)
        .task { await store.loadPreferredVersion() }
        // Rebuilt when the imdbID resolves — the engine cannot query the indexers without it.
        .task(id: store.imdbID) {
            acquisition = session.makeAcquisition(for: store.item, imdbID: store.imdbID,
                                                  originalLanguage: store.originalLanguage)
        }
        .onChange(of: acquisition?.phase) { _, phase in
            guard case let .ready(request) = phase else { return }
            session.libraryStore?.reload()     // a new torrent landed in RD
            // Its job is done once there is something to play. The cover reset it on dismissal;
            // a push has no dismissal hook, and coming back re-reads the watch state on appear.
            acquisition?.reset()
            if isOnScreen { openDestination(.play(request)) }
        }
        .onAppear { isOnScreen = true }
        .onDisappear { isOnScreen = false }
        .background(CanvasBackground())
        .fullScreenCover(isPresented: $expandTrailer) {
            if let u = trailerURL { FullScreenTrailer(url: u) }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(item.title).screenTitle()
            Text(metaLine).calloutText().foregroundStyle(Theme.Palette.textSecondary)
            if let franchise = store.franchise {
                Text("Film \(franchise.position) of \(franchise.count)  ·  \(franchise.name)")
                    .calloutText().foregroundStyle(Theme.Palette.gold)
            }
            if !store.directors.isEmpty {
                CreditNamesRow(label: store.directors.count == 1 ? "Director" : "Directors",
                               people: store.directors)
            }
            if store.bestSource != nil || store.hebrewChip != nil {
                HStack(spacing: 16) {
                    if let best = store.bestSource { QualityChips(parsed: best.parsed) }
                    if let chip = store.hebrewChip {
                        HebrewBadge(HebrewIndicator(chip: chip), prominent: true)
                    } else {
                        // Holds the row at the badge's height, so the chip landing does not push
                        // the page — and the Play button focus was just placed on — down.
                        HebrewBadge(.inFile, prominent: true).hidden()
                    }
                }
            }
            RatingsRow(ratings: store.ratings, letterboxd: store.letterboxdRating)
            if let overview = store.overview {
                ExpandableOverview(text: overview, title: item.title)
            }
            actions
            acquisitionStatus
            UserRatingRow(store: store)
            WatchDatesLine(summary: store.watchSummary, since: store.historySince)
            if let tmdb = item.tmdbID, offersDownload(tmdbID: tmdb) {
                MovieDownloadSection(tmdbID: tmdb, title: item.title, posterPath: item.posterPath,
                                     imdbID: store.imdbID, originalLanguage: store.originalLanguage)
            }
        }
        // On the container, not on WatchDatesLine: that view renders NOTHING until the summary it
        // is waiting for arrives, so hanging the load that produces it off a conditionally-empty
        // body makes it depend on SwiftUI keeping an empty view in the tree.
        .task { await store.loadWatchSummary() }
    }

    private var metaLine: String {
        var parts: [String] = []
        if let y = item.year { parts.append(String(y)) }
        if let r = store.runtime { parts.append("\(r) min") }
        if let language = store.languageName { parts.append(language) }
        if !store.genres.isEmpty { parts.append(store.genres.prefix(3).joined(separator: " · ")) }
        return parts.joined(separator: "  ·  ")
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: 16) {
            if let best = store.bestSource {
                NavigationLink(value: store.playRequest(source: best, episode: nil, label: item.title)) {
                    Label(resumeSeconds != nil ? "Resume \(Timecode.format(resumeSeconds!))" : "Play",
                          systemImage: "play.fill")
                }
                .buttonStyle(SeretActionButtonStyle(prominent: true))
                .focused($initialFocus, equals: .play)

                if resumeSeconds != nil {
                    NavigationLink(value: store.playRequest(source: best, episode: nil,
                                                            label: item.title, fromStart: true)) {
                        Label("From Start", systemImage: "gobackward")
                    }
                    .buttonStyle(SeretActionButtonStyle())
                }
            } else {
                // Not in the library: Play still means play. It finds the best instantly-available
                // release, adds it, and starts — the old Add screen's whole job, on this page.
                //
                // Never `.disabled`: a disabled button cannot hold tvOS focus. Disabled while busy,
                // the press that started the search threw focus off the button (to the director pill
                // or Versions, so the next Select opened THAT); disabled until the IMDb id resolved,
                // the page's default focus had nothing to land on when it opened. Busy is said in the
                // label, and the action ignores a press it cannot act on yet — the engine cannot
                // query an indexer before the IMDb id arrives (pressing then used to fail with "Not
                // signed in to Real-Debrid", a reason that was not only unhelpful but untrue).
                Button {
                    guard !acquiring else { return }
                    guard let acquisition, store.imdbID != nil else {
                        // Still loading, the id is on its way and a press is merely early. Loaded
                        // without one — TMDB has no IMDb id, or the details never arrived — the
                        // button used to do nothing at all, which reads as a dead remote.
                        switch store.richState {
                        case .loaded:
                            playUnavailable = "Can\u{2019}t search for versions of this title \u{2014} TMDB has no IMDb id for it."
                        case .failed:
                            playUnavailable = "Couldn\u{2019}t load this title\u{2019}s details. Check your connection and try again."
                        default:
                            break
                        }
                        return
                    }
                    playUnavailable = nil
                    Task { await acquisition.playBest(.movie) }
                } label: {
                    Label(acquiringLabel, systemImage: acquiring ? "hourglass" : "play.fill")
                }
                .buttonStyle(SeretActionButtonStyle(prominent: true))
                .focused($initialFocus, equals: .play)
            }

            // Reachable whether or not you own the title — on an un-owned one it IS the way to pick
            // a specific release.
            if let hit = otherVersionsHit {
                NavigationLink(value: BrowseDestination.versions(hit)) {
                    Label("Versions", systemImage: "square.stack.3d.up")
                }
                .buttonStyle(SeretActionButtonStyle())
            }

            // Its own control rather than a line in the More menu: it is the one thing on this page
            // you do to a film you have NOT watched, which is most of what reaches an unowned title.
            if let film = WatchlistFilm(item: item), let watchlist {
                let on = watchlist.contains(tmdbID: film.tmdbID)
                Button {
                    // A press while the last one is still in flight is ignored rather than the
                    // button being disabled — disabling it threw focus off it, usually onto Play.
                    guard !watchlist.isInFlight(tmdbID: film.tmdbID) else { return }
                    Task { await watchlist.toggle(film: film) }
                } label: {
                    Label(on ? "On Watchlist" : "Watchlist",
                          systemImage: on ? "bookmark.fill" : "bookmark")
                }
                .buttonStyle(SeretActionButtonStyle())
            }

            // Everything rare or destructive lives here — off the primary path so it can't be mis-hit.
            Menu {
                Button {
                    Task {
                        await store.setWatched(!isWatched, contentKey: contentKey,
                                               source: store.bestSource)
                    }
                } label: {
                    Label(isWatched ? "Mark Unwatched" : "Mark Watched",
                          systemImage: isWatched ? "checkmark.circle.fill" : "checkmark.circle")
                }

                Button {
                    Task { await store.toggleMyList(contentKey: item.id) }
                } label: {
                    Label(store.inMyList ? "In My List" : "Add to My List",
                          systemImage: store.inMyList ? "checkmark" : "plus")
                }

                if trailerURL != nil {
                    Button { expandTrailer = true } label: {
                        Label("Trailer", systemImage: "play.rectangle.fill")
                    }
                }

                if !item.sources.isEmpty {
                    Button(role: .destructive) { onRemove() } label: {
                        Label("Remove from Library", systemImage: "trash")
                    }
                }
            } label: {
                Label("More", systemImage: "ellipsis")
            }
            .buttonStyle(SeretActionButtonStyle())
        }
        // Each horizontal row is one target for vertical travel, and a section only counts when its
        // FRAME intersects the direction of travel — so widen to the page first, then section.
        // Otherwise a control further right on the row below (a star, a version) has nothing above.
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
    }

    /// True while a release is being found or added.
    /// The download offer appears once there is a reason for it: Play looked and found nothing it
    /// could start, or a download of this film already exists. It used to sit on every film you
    /// don't own, announcing "No cached version exists" before anything had been checked — and
    /// inviting a slow download where Play would have started the film at once.
    private func offersDownload(tmdbID: Int) -> Bool {
        if session.downloadStore?.status(forContentKey: DownloadKey.movie(tmdbID: tmdbID)) != nil {
            return true
        }
        guard store.bestSource == nil else { return false }
        switch acquisition?.phase {
        case .noneCached, .failed: return true
        default: return false
        }
    }

    private var acquiring: Bool {
        switch acquisition?.phase {
        case .finding, .adding: true
        default: false
        }
    }

    private var acquiringLabel: String {
        switch acquisition?.phase {
        case .finding: "Finding a version…"
        case .adding: "Starting…"
        default: "Play"
        }
    }

    /// What the acquisition is waiting on or failed at. `.noneCached` falls through to the existing
    /// Request Download section below, which already renders whenever there is no playable source.
    @ViewBuilder private var acquisitionStatus: some View {
        if let playUnavailable {
            Label(playUnavailable, systemImage: "exclamationmark.triangle")
                .font(.seretCallout).foregroundStyle(.orange)
        }
        switch acquisition?.phase {
        case .noneCached:
            Label("No instantly-playable version. Request a download below.",
                  systemImage: "magnifyingglass")
                .font(.seretCallout).foregroundStyle(Theme.Palette.textSecondary)
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.seretCallout).foregroundStyle(.orange)
        default:
            EmptyView()
        }
    }

    private var resumeSeconds: Double? {
        return watch?.resumePosition
    }
    private var isWatched: Bool { watch?.finished == true }

    /// The title, as the Add pipeline wants it — `VersionsScreen` resolves the same cached/uncached
    /// release list from it, without the Add screen's hero. Needs a TMDB id to search.
    private var otherVersionsHit: SearchHit? {
        guard let tmdb = item.tmdbID else { return nil }
        return SearchHit(result: TMDBSearchResult(
            id: tmdb, title: item.title, name: nil, releaseDate: nil, firstAirDate: nil,
            posterPath: item.posterPath, overview: nil, voteAverage: nil), kind: .movie)
    }

    private var versionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // "Find Other Versions" moved up into the action row, where it is reachable on a title
            // you do not own too (this section only renders once you own something).
            Text("Versions").sectionTitle().frame(maxWidth: 1100, alignment: .leading)
            ForEach(store.versions, id: \.self) { src in
                let hebrew = HebrewIndicator(store.hebrew(for: src))
                NavigationLink(value: store.playRequest(source: src, episode: nil, label: item.title)) {
                    VStack(alignment: .leading, spacing: 10) {
                        // Hebrew inside the file is always in sync: a line of its own, on top, as
                        // in the Versions list.
                        if hebrew == .inFile { HebrewBadge(.inFile) }
                        HStack(spacing: 16) {
                            Image(systemName: store.isActive(src) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(store.isActive(src)
                                                 ? Theme.Palette.gold : Theme.Palette.textSecondary)
                            QualityChips(parsed: src.parsed)
                            if hebrew == .matched { HebrewBadge(.matched) }
                            Spacer()
                            if let detail = versionDetail(src) {
                                Text(detail)
                                    .font(.seret(Theme.Typography.captionSize, .medium))
                                    .foregroundStyle(Theme.Palette.textSecondary)
                                    .lineLimit(1)
                            }
                            Image(systemName: "play.fill")
                        }
                    }
                }
                .buttonStyle(SeretRowStyle())
                .contextMenu {
                    if !store.isActive(src) {
                        Button("Make Default") { Task { await store.chooseVersion(src) } }
                    }
                    if store.preferredSourceKey != nil {
                        Button("Use Best Automatically") {
                            Task { await store.clearPreferredVersion() }
                        }
                    }
                    Button("Delete Version", systemImage: "trash", role: .destructive) {
                        onRemoveVersion(src)
                    }
                }
            }
        }
        // Inner frame keeps the rows 1100pt wide; the outer one widens only the FOCUS target to the
        // full page, so travelling UP from a poster on the right of the "More Like This" rail lands
        // in Versions instead of dying on empty space.
        .frame(maxWidth: 1100, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
    }

    /// Release group and size — what tells otherwise identical versions apart. Three rows reading
    /// "2160p · BluRay · HEVC · DTS" and nothing else left the choice between them to luck.
    private func versionDetail(_ src: MediaSource) -> String? {
        var parts: [String] = []
        if let group = src.parsed.releaseGroup, !group.isEmpty { parts.append(group) }
        if let bytes = src.sizeBytes, bytes > 0 {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

#Preview {
    let s = MediaSource(torrentID: "t", fileID: nil, restrictedLink: "l",
                        parsed: ParsedRelease(title: "Dune", resolution: "2160p",
                                              source: "REMUX", videoCodec: "HEVC"))
    let item = MediaItem(id: "1", kind: .movie, title: "Dune: Part Two", year: 2024,
                         sources: [s], seasons: [], tmdbID: nil,
                         overview: "Paul Atreides unites with the Fremen…")
    return NavigationStack {
        MovieDetailView(store: DetailStore(item: item, details: PreviewDetails(), watch: nil))
    }
}

/// Inert provider for previews (never called when tmdbID is nil).
private struct PreviewDetails: MediaDetailsProviding {
    func movieDetails(tmdbID: Int) async throws -> TMDBMovieDetails { throw CancellationError() }
    func tvDetails(tmdbID: Int) async throws -> TMDBTVDetails { throw CancellationError() }
    func seasonEpisodes(tvID: Int, season: Int) async throws -> [TMDBEpisodeDetails] { [] }
}

/// Request Download for a movie with no cached/playable version (tvOS). Mirrors the iOS Detail
/// section: fetch the best uncached release via the shared Add seam, start an RD download, and show
/// live progress from the app-wide `DownloadStore`. When it finishes the title flips into the
/// library and Play lights up.
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
        VStack(alignment: .leading, spacing: 14) {
            // ONE button through every state, its label saying what is happening. It used to be
            // disabled on press and then replaced by a progress view — and a focused view that is
            // disabled or replaced throws tvOS focus off it, to the top of the page.
            Button { request(status) } label: {
                Label(buttonTitle(status), systemImage: buttonIcon(status))
            }
            .buttonStyle(SeretActionButtonStyle())
            if case .downloading = status?.phase {
                ProgressView(value: status?.fraction ?? 0).frame(maxWidth: 600)
            }
            Text(caption(status))
                .font(.seretCallout).foregroundStyle(.secondary)
                .frame(maxWidth: 1000, alignment: .leading)
        }
    }

    /// Only a press that can start something does: nothing while a request or download is under way.
    private func request(_ status: DownloadStatus?) {
        guard !requesting else { return }
        switch status?.phase {
        case nil, .failed: break
        default: return
        }
        Task {
            requesting = true
            defer { requesting = false }
            var candidates: [CachedStream] = []
            if let imdbID, let add = session.makeAddStore(imdbID: imdbID, kind: .movie,
                                                          originalLanguage: originalLanguage,
                                                          subtitleTarget: .movie(tmdbID: tmdbID, title: title,
                                                                                 year: nil)) {
                candidates = await add.uncachedCandidates()
            }
            let target = DownloadTarget(contentKey: DownloadKey.movie(tmdbID: tmdbID),
                                        tmdbID: tmdbID, title: title, kind: .movie,
                                        posterPath: posterPath)
            await session.downloadStore?.request(target, candidates: candidates)
        }
    }

    private func buttonTitle(_ status: DownloadStatus?) -> String {
        switch status?.phase {
        case .queued: return "Starting download\u{2026}"
        case .downloading: return "Downloading \(Int((status?.fraction ?? 0) * 100))%"
        case .ready: return "Downloaded"
        case .failed: return "Try Another Version"
        case nil: return requesting ? "Starting download\u{2026}" : "Request Download"
        }
    }

    private func buttonIcon(_ status: DownloadStatus?) -> String {
        switch status?.phase {
        case .queued, .downloading: return "arrow.down.circle.fill"
        case .ready: return "checkmark.circle.fill"
        case .failed: return "arrow.clockwise"
        case nil: return requesting ? "hourglass" : "arrow.down.circle"
        }
    }

    private func caption(_ status: DownloadStatus?) -> String {
        switch status?.phase {
        case .queued, .downloading: return "Real\u{2011}Debrid is fetching it. It'll appear here when it's ready."
        case .ready: return "It's in your library."
        case .failed(let reason): return reason
        case nil: return "Nothing can start instantly. Request a download and it'll appear here when it's ready."
        }
    }
}
