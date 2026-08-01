import DebridCore
import DebridUI
import SwiftUI

/// Movie Detail: backdrop hero, metadata, overview, Play/Resume, Versions, Mark Watched.
struct MovieDetailView: View {
    let store: DetailStore
    var onRemove: () -> Void = {}

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

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                TrailerHero(tmdbID: item.tmdbID, kind: .movie,
                            backdropPath: store.backdropPath, posterFallback: item.posterPath,
                            resolvedURL: $trailerURL)
                VStack(alignment: .leading, spacing: 36) {
                    hero.frame(maxWidth: .infinity, alignment: .leading)
                    if !store.versions.isEmpty { versionsSection }
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
        .background(CanvasBackground())
        .fullScreenCover(isPresented: $expandTrailer) {
            if let u = trailerURL { FullScreenTrailer(url: u) }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(item.title).screenTitle()
            Text(metaLine).calloutText().foregroundStyle(Theme.Palette.textSecondary)
            if let director = store.director {
                Text("Director: \(director)").calloutText()
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            if let best = store.bestSource { QualityChips(parsed: best.parsed) }
            RatingsRow(ratings: store.ratings, community: store.communityScore)
            if let overview = store.overview {
                Text(overview).bodyText().frame(maxWidth: 1100, alignment: .leading).lineLimit(4)
            }
            actions
            UserRatingRow(store: store)
            WatchDatesLine(summary: store.watchSummary, since: store.historySince)
                .task { await store.loadWatchSummary() }
            if let tmdb = item.tmdbID,
               store.bestSource == nil
                || session.downloadStore?
                    .status(forContentKey: DownloadKey.movie(tmdbID: tmdb)) != nil {
                MovieDownloadSection(tmdbID: tmdb, title: item.title, posterPath: item.posterPath,
                                     imdbID: store.imdbID, originalLanguage: store.originalLanguage)
            }
        }
    }

    private var metaLine: String {
        var parts: [String] = []
        if let y = item.year { parts.append(String(y)) }
        if let r = store.runtime { parts.append("\(r) min") }
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
            }

            // Everything rare or destructive lives here — off the primary path so it can't be mis-hit.
            Menu {
                Button {
                    Task {
                        await store.setWatched(!isWatched, contentKey: contentKey,
                                               source: store.bestSource ?? item.sources[0])
                    }
                } label: {
                    Label(isWatched ? "Mark Unwatched" : "Mark Watched",
                          systemImage: isWatched ? "checkmark.circle.fill" : "checkmark.circle")
                }
                .disabled(item.sources.isEmpty)

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

                Button(role: .destructive) { onRemove() } label: {
                    Label("Remove from Library", systemImage: "trash")
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

    private var resumeSeconds: Double? {
        guard let w = watch, !w.finished, w.positionSeconds > 0 else { return nil }
        return w.positionSeconds
    }
    private var isWatched: Bool { watch?.finished == true }

    /// The Add flow for this title — it already hosts the full cached/uncached versions browser,
    /// so Detail routes there rather than growing a second one. Needs a TMDB id to search.
    private var otherVersionsHit: SearchHit? {
        guard let tmdb = item.tmdbID else { return nil }
        return SearchHit(result: TMDBSearchResult(
            id: tmdb, title: item.title, name: nil, releaseDate: nil, firstAirDate: nil,
            posterPath: item.posterPath, overview: nil, voteAverage: nil), kind: .movie)
    }

    private var versionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 24) {
                Text("Versions").sectionTitle()
                Spacer()
                if let hit = otherVersionsHit {
                    NavigationLink(value: BrowseDestination.add(hit)) {
                        Label("Find Other Versions", systemImage: "square.stack.3d.up")
                    }
                    .buttonStyle(SeretActionButtonStyle())
                }
            }
            .frame(maxWidth: 1100)
            ForEach(store.versions, id: \.self) { src in
                NavigationLink(value: store.playRequest(source: src, episode: nil, label: item.title)) {
                    HStack(spacing: 16) {
                        Image(systemName: store.isActive(src) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(store.isActive(src)
                                             ? Theme.Palette.gold : Theme.Palette.textSecondary)
                        QualityChips(parsed: src.parsed)
                        Spacer()
                        Image(systemName: "play.fill")
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
        VStack(alignment: .leading, spacing: 16) {
            if requesting && status == nil {
                ProgressView("Starting download…")
            } else if case .queued = status?.phase {
                ProgressView("Starting download…")
            } else if case .downloading = status?.phase {
                let pct = Int((status?.fraction ?? 0) * 100)
                Label("Downloading \(pct)% to Real-Debrid…", systemImage: "arrow.down.circle.fill")
                ProgressView(value: status?.fraction ?? 0).frame(maxWidth: 600)
                Text("It'll appear here when it's ready.").font(.callout).foregroundStyle(.secondary)
            } else if case .failed(let reason) = status?.phase {
                Label(reason, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                requestButton("Try Another Version")
            } else {
                Text("No cached version exists. Start a download and it'll appear here when it's ready.")
                    .font(.callout).foregroundStyle(.secondary).frame(maxWidth: 1000, alignment: .leading)
                requestButton("Request Download")
            }
        }
        .font(.title3)
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
            .disabled(requesting || imdbID == nil)
    }
}
