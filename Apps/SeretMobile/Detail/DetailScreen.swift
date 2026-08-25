import DebridCore
import DebridUI
import SwiftUI

/// Wraps a `PlaybackRequest` so it can drive a `.fullScreenCover(item:)`.
struct PlaybackPresentation: Identifiable {
    let id = UUID()
    let request: PlaybackRequest
}

/// Owns the per-title `DetailStore`, dispatches movie vs. show, and presents the player
/// full-screen (covering the iPad sidebar). Presented itself as a full-screen cover.
struct DetailScreen: View {
    @State private var store: DetailStore
    @State private var playback: PlaybackPresentation?
    @State private var confirmingRemove = false
    @State private var removeError: String?
    /// "More Like This" destinations. Presented from HERE, not through `AppRouter`: this screen is
    /// itself a cover owned by the shell, and the shell can't stack a second cover on top of it.
    @State private var similarDetail: MediaItem?
    /// The title whose full version list is open (from "Versions" / "Find Other").
    @State private var versionsHit: SearchHit?
    /// The EPISODE whose full version list is open. Separate from `versionsHit` because the cover
    /// needs the season and number too, and only one of the two is ever presented.
    @State private var episodeVersions: EpisodeVersionsTarget?
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    init(item: MediaItem, details: MediaDetailsProviding, watch: WatchProgressProviding?,
         profileID: String? = nil, myList: MyListProviding? = nil, ratings: RatingsProviding? = nil,
         versionPrefs: VersionPreferring? = nil) {
        _store = State(initialValue: DetailStore(item: item, details: details, watch: watch,
                                                 profileID: profileID, myList: myList, ratings: ratings,
                                                 versionPrefs: versionPrefs))
    }

    var body: some View {
        NavigationStack {
            Group {
                switch store.item.kind {
                case .movie: MovieDetail(store: store, onPlay: present,
                                        onRemoveVersion: { src in
                                            Task {
                                                await session.libraryStore?.removeVersion(store.item, source: src)
                                                // Drop it from this screen too — `item` is a snapshot.
                                                await store.forgetVersion(src)
                                            }
                                        },
                                        onOpenTitle: { similarDetail = $0 },
                                        onAddTitle: { versionsHit = $0 })
                case .show:  ShowDetail(
                                store: store, onPlay: present,
                                makeSeasonDownload: { imdb, season, lang in
                                    session.makeSeasonDownload(imdbID: imdb, season: season, originalLanguage: lang)
                                },
                                makeEpisodeDownload: { imdb, season, episode, lang in
                                    session.makeAddStore(imdbID: imdb, kind: .series(season: season, episode: episode),
                                                         originalLanguage: lang)
                                },
                                onSeasonAdded: { session.libraryStore?.retry() },
                                onOpenTitle: { similarDetail = $0 },
                                onAddTitle: { versionsHit = $0 },
                                onFindEpisodeVersions: { hit, season, number in
                                    episodeVersions = EpisodeVersionsTarget(hit: hit, season: season,
                                                                            number: number)
                                })
                }
            }
            .task {
                await store.load()
                // Warm the RD unrestrict for what Play would start (the movie's best source /
                // the show's next-up episode) — tapping Play then skips the network round-trip.
                let source = store.item.kind == .movie ? store.bestSource : store.nextEpisode()?.source
                if let source { session.prefetchPlayback(for: source) }
            }
            .task { await store.loadMyList(contentKey: store.item.id) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "chevron.down").font(.headline) }
                        .tint(Theme.Palette.gold)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(store.inMyList ? "In My List" : "Add to My List",
                               systemImage: store.inMyList ? "checkmark" : "plus") {
                            Task { await store.toggleMyList(contentKey: store.item.id) }
                        }
                        Button("Remove from Library", systemImage: "trash", role: .destructive) {
                            confirmingRemove = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.headline)
                    }
                    .tint(Theme.Palette.gold)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .confirmationDialog("Remove \u{201C}\(store.item.title)\u{201D} from your library?",
                                isPresented: $confirmingRemove, titleVisibility: .visible) {
                Button("Remove", role: .destructive) { performRemove() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This deletes it from your Real\u{2011}Debrid account. You can re\u{2011}add it later by searching.")
            }
            .alert("Couldn\u{2019}t Remove", isPresented: Binding(
                get: { removeError != nil }, set: { if !$0 { removeError = nil } })) {
                Button("OK", role: .cancel) { removeError = nil }
            } message: {
                Text(removeError ?? "")
            }
        }
        // Re-read watch state when the player closes so Resume · <time> reflects the position
        // the player just recorded (the underlying screen's .task does not re-run on dismiss).
        //
        // Home is refreshed here too. It watches `router.playback`, but a title page presents the
        // player through its OWN cover — so nothing told Home that Continue Watching had changed,
        // and the rail stayed as it was until something else happened to rebuild it.
        .fullScreenCover(item: $playback, onDismiss: {
            Task {
                await store.reloadWatch()
                await session.refreshHome()
            }
        }) { presented in
            PlayerHost(request: presented.request, app: session, onExit: { playback = nil })
        }
        // A suggested title the viewer already owns opens its own Detail on top of this one.
        // `AnyView` is load-bearing: without it DetailScreen's body type would contain itself.
        .fullScreenCover(item: $similarDetail) { item in
            if let details = session.detailsProvider {
                AnyView(DetailScreen(item: item, details: details, watch: session.watchStore,
                                     profileID: session.activeProfileID,
                                     myList: session.myListStore,
                                     ratings: session.ratingsProvider,
                                     versionPrefs: session.versionPreferences))
            }
        }
        // "Versions" — the full cached/uncached release list for this title, owned or not.
        .fullScreenCover(item: $versionsHit) { hit in
            VersionsScreen(hit: hit, onPlay: present)
        }
        // The same list, scoped to one episode of a show.
        .fullScreenCover(item: $episodeVersions) { target in
            VersionsScreen(hit: target.hit,
                           episode: (season: target.season, number: target.number),
                           onPlay: present)
        }
    }

    private func present(_ request: PlaybackRequest) {
        playback = PlaybackPresentation(request: request)
    }

    private func performRemove() {
        guard let library = session.libraryStore else { return }
        Task {
            await library.remove(store.item)
            if case .failed(let message) = library.removal {
                removeError = message
                library.clearRemovalError()
            } else {
                dismiss()
            }
        }
    }
}

/// Full-bleed backdrop (or poster fallback) + darkening scrim behind a Detail screen.
struct DetailBackdrop: View {
    let path: String?
    let posterFallback: String?

    var body: some View {
        Group {
            if let url = TMDBClient.imageURL(path: path, size: "w1280")
                ?? TMDBClient.imageURL(path: posterFallback, size: "w780") {
                RemoteImage(url: url) { Color.black }
            } else {
                LinearGradient(colors: [.gray.opacity(0.3), .black], startPoint: .top, endPoint: .bottom)
            }
        }
        .overlay(LinearGradient(stops: [
            .init(color: .black.opacity(0.25), location: 0.0),
            .init(color: Theme.Palette.canvas.opacity(0.85), location: 0.6),
            .init(color: Theme.Palette.canvas, location: 1.0),
        ], startPoint: .top, endPoint: .bottom))
        .ignoresSafeArea()
    }
}

/// Quality / source / codec chips for a parsed release.
struct QualityChipRow: View {
    let parsed: ParsedRelease
    private var chips: [String] {
        [parsed.resolution, parsed.source, parsed.videoCodec, parsed.audioCodec].compactMap { $0 }
    }
    var body: some View {
        HStack(spacing: 6) {
            if chips.isEmpty {
                // No parseable quality metadata — show the release name so the row is never blank
                // and an odd version stays identifiable.
                Text(parsed.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .lineLimit(1)
            } else {
                ForEach(chips, id: \.self) { QualityChip(text: $0) }
            }
        }
    }
}

/// Fallback when a player can't be built (e.g. signed out / no Real-Debrid session).
struct PlayerPlaceholder: View {
    let request: PlaybackRequest
    var body: some View {
        ContentUnavailableView {
            Label(request.label, systemImage: "play.slash")
        } description: {
            Text("Playback isn't available right now.")
        }
    }
}

/// One episode's version list, as a presentable item.
private struct EpisodeVersionsTarget: Identifiable {
    let hit: SearchHit
    let season: Int
    let number: Int
    var id: String { "\(hit.result.id)s\(season)e\(number)" }
}
