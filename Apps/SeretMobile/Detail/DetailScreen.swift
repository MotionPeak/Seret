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
    /// Owned by this page rather than read from the shell: Detail is a full-screen cover, and an
    /// object that does not cross that boundary is a trap. The syncer underneath is shared, so the
    /// mirror stays consistent with every other surface.
    @State private var watchlist: WatchlistMarks?
    @State private var removeError: String?
    /// "More Like This" destinations. Presented from HERE, not through `AppRouter`: this screen is
    /// itself a cover owned by the shell, and the shell can't stack a second cover on top of it.
    @State private var similarDetail: MediaItem?
    /// The title whose full version list is open (from "Versions" / "Find Other").
    @State private var versionsHit: SearchHit?
    /// The EPISODE whose full version list is open. Separate from `versionsHit` because the cover
    /// needs the season and number too, and only one of the two is ever presented.
    @State private var episodeVersions: EpisodeVersionsTarget?
    /// The page has scrolled past the hero's info: the bar takes the title (and, on iOS 18, its
    /// frosted background). See `titlePageScroll`.
    @State private var heroScrolled = false
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    init(item: MediaItem, details: MediaDetailsProviding, watch: WatchProgressProviding?,
         profileID: String? = nil, myList: MyListProviding? = nil, ratings: RatingsProviding? = nil,
         versionPrefs: VersionPreferring? = nil,
         letterboxd: LetterboxdRatingProviding? = nil,
         subtitleEvidence: SubtitleEvidenceProviding? = nil) {
        _store = State(initialValue: DetailStore(item: item, details: details, watch: watch,
                                                 profileID: profileID, myList: myList, ratings: ratings,
                                                 versionPrefs: versionPrefs,
                                                 letterboxd: letterboxd,
                                                 subtitleEvidence: subtitleEvidence))
    }

    var body: some View {
        NavigationStack {
            Group {
                switch store.item.kind {
                case .movie: MovieDetail(store: store, heroScrolled: $heroScrolled, onPlay: present,
                                        onRemoveVersion: { src in
                                            Task {
                                                await session.libraryStore?.removeVersion(store.item, source: src)
                                                // Drop it from this screen too — `item` is a snapshot.
                                                await store.forgetVersion(src)
                                            }
                                        },
                                        onOpenTitle: { similarDetail = $0 },
                                        onAddTitle: { versionsHit = $0 },
                                        onRemoveTitle: { confirmingRemove = true })
                case .show:  ShowDetail(
                                store: store, heroScrolled: $heroScrolled, onPlay: present,
                                makeSeasonDownload: { imdb, season, lang in
                                    session.makeSeasonDownload(imdbID: imdb, season: season, originalLanguage: lang)
                                },
                                makeEpisodeDownload: { imdb, season, episode, lang in
                                    session.makeAddStore(imdbID: imdb, kind: .series(season: season, episode: episode),
                                                         originalLanguage: lang,
                                                         subtitleTarget: store.item.tmdbID.map {
                                                             .episode(showTmdbID: $0, title: store.item.title,
                                                                      year: store.item.year, season: season,
                                                                      episode: episode)
                                                         })
                                },
                                onSeasonAdded: { session.libraryStore?.retry() },
                                onOpenTitle: { similarDetail = $0 },
                                onRemoveTitle: { confirmingRemove = true },
                                onFindEpisodeVersions: { hit, season, number in
                                    episodeVersions = EpisodeVersionsTarget(hit: hit, season: season,
                                                                            number: number)
                                })
                }
            }
            .task {
                await store.load()
                // Warm the RD unrestrict for what Play would start (the movie's best source / the
                // show's next-up episode) — tapping Play then skips the network round-trip.
                let source = store.item.kind == .movie ? store.bestSource : store.nextEpisode()?.source
                if let source { session.prefetchPlayback(for: source) }
            }
            // A movie's Play target can change while the page is open — Hebrew evidence or a chosen
            // default lands — so a change warms the new target. Never the first value: that is only the
            // pick before the page knows better, and warming it cost an extra unrestrict per visit.
            .onChange(of: store.bestSource) { _, source in
                if store.item.kind == .movie, let source { session.prefetchPlayback(for: source) }
            }
            // The title became yours while this page was open (played from here, a season added,
            // a download landing): take the library's item, or Play would acquire it AGAIN and
            // start it from 0:00.
            .task(id: ownedInLibrary) {
                if let owned = ownedInLibrary { await store.adopt(owned) }
            }
            .task { await store.loadMyList(contentKey: store.item.id) }
            // Movies only — Letterboxd has no watchlist a show can go on — so a show page does not
            // pay for an object it cannot use.
            .task {
                guard store.item.kind == .movie else { return }
                if watchlist == nil { watchlist = session.makeWatchlistMarks() }
                await watchlist?.load()
            }
            .environment(watchlist)
            .watchlistChangeConfirmation(marks: watchlist, tmdbID: store.item.tmdbID) { outcome in
                WatchlistChangeBar(outcome: outcome)
            }
            // The glass navigation bar (g3): a close circle on the left; the page's own ⋯ menu on the
            // right (each page adds it — its items are the page's). The title arrives only once the
            // hero's own logo has scrolled away, so the art is never captioned twice.
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { ToolbarGlassIcon(systemImage: "chevron.down") }
                        .tint(Theme.Palette.focus)
                        .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .principal) {
                    Text(store.item.title)
                        .font(.headline)
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .lineLimit(1)
                        .opacity(heroScrolled ? 1 : 0)
                        .animation(Theme.Motion.fade, value: heroScrolled)
                        .accessibilityHidden(!heroScrolled)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .titlePageBar()
            // Once the page is scrolled, a shade fades in under the status bar and the glass bar,
            // so the text scrolling up never runs through the chevron or the title (audit #4). Ours
            // on both iOS versions: the page runs under the bar (`ignoresSafeArea`), which keeps
            // UIKit's own scroll-edge treatment from knowing there is content beneath it.
            .overlay(alignment: .top) {
                GeometryReader { geo in
                    LinearGradient(stops: [.init(color: Theme.Palette.canvas, location: 0),
                                           .init(color: Theme.Palette.canvas.opacity(0.94), location: 0.7),
                                           .init(color: Theme.Palette.canvas.opacity(0), location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: geo.safeAreaInsets.top + 78)
                        .ignoresSafeArea(edges: .top)
                }
                .opacity(heroScrolled ? 1 : 0)
                .animation(Theme.Motion.fade, value: heroScrolled)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
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
                                     versionPrefs: session.versionPreferences,
                                     letterboxd: session.letterboxdRatingProvider,
                                     subtitleEvidence: session.subtitleEvidence))
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

    /// The library's item for this title, read live (see the `.task(id:)` that adopts it).
    private var ownedInLibrary: MediaItem? {
        store.item.tmdbID.flatMap { session.libraryStore?.ownedItem(tmdbID: $0, kind: store.item.kind) }
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

/// Quality / source / codec chips for a parsed release — as many WHOLE chips as fit, dropping the
/// least telling first (audio, then codec). Squeezed below their text's width the chips broke one
/// character per line ("REMU / X").
struct QualityChipRow: View {
    let parsed: ParsedRelease
    private var chips: [String] {
        [parsed.resolution, parsed.source, parsed.videoCodec, parsed.audioCodec].compactMap { $0 }
    }
    var body: some View {
        if chips.isEmpty {
            // No parseable quality metadata — show the release name so the row is never blank
            // and an odd version stays identifiable.
            Text(parsed.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.Palette.textSecondary)
                .lineLimit(1)
        } else {
            ViewThatFits(in: .horizontal) {
                ForEach(Array(stride(from: chips.count, to: 0, by: -1)), id: \.self) { n in
                    HStack(spacing: 6) {
                        ForEach(chips.prefix(n), id: \.self) { QualityChip(text: $0).fixedSize() }
                    }
                }
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
