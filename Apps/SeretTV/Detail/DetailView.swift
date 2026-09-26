import DebridCore
import DebridUI
import SwiftUI

struct DetailView: View {
    @State private var store: DetailStore
    @State private var confirmingRemove = false
    /// The version awaiting a delete confirmation (nil = no sheet).
    @State private var pendingVersionRemoval: MediaSource?
    @State private var removeError: String?
    @State private var downloadingEpisodeID: String?
    @State private var episodePlayback: EpisodePlayback?
    @State private var episodeError: String?
    /// Finds, adds and plays an episode you do not have — the same engine the movie page uses.
    @State private var acquirer: TitleAcquirer?
    /// Owned by this page rather than read from the shell: Detail is reached by a push AND from
    /// inside covers, and an object that does not cross one of those boundaries is a trap. The
    /// syncer underneath is shared, so the mirror stays consistent with every other surface.
    @State private var watchlist: WatchlistMarks?
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    /// Wraps a just-downloaded episode's request for `.fullScreenCover(item:)` (downloaded episodes
    /// play via the value-nav link in `EpisodeRow`; this covers the download-then-play path).
    private struct EpisodePlayback: Identifiable { let id = UUID(); let request: PlaybackRequest }

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
        Group {
            switch store.item.kind {
            case .movie: MovieDetailView(store: store, onRemove: { confirmingRemove = true },
                                         onRemoveVersion: { pendingVersionRemoval = $0 })
            case .show:  ShowDetailView(
                store: store, onRemove: { confirmingRemove = true },
                makeSeasonDownload: { imdb, season, lang in
                    session.makeSeasonDownload(imdbID: imdb, season: season, originalLanguage: lang)
                },
                onSeasonAdded: { session.libraryStore?.retry() },
                onDownloadEpisode: downloadAndPlayEpisode,
                onPlayEpisode: { season, number in
                    playEpisode(season: season, number: number, id: "s\(season)e\(number)")
                },
                downloadingEpisodeID: downloadingEpisodeID)
            }
        }
        .task(id: store.imdbID) {
            acquirer = session.makeTitleAcquirer(for: store, onAdded: { session.libraryStore?.retry() })
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
        .task { await store.loadMyList(contentKey: store.item.id) }
        // Movies only — Letterboxd has no watchlist a show can go on — so a show page does not pay
        // for an object it cannot use.
        .task {
            guard store.item.kind == .movie else { return }
            if watchlist == nil { watchlist = session.makeWatchlistMarks() }
            await watchlist?.load()
        }
        .environment(watchlist)
        .watchlistChangeConfirmation(marks: watchlist, tmdbID: store.item.tmdbID) { outcome in
            WatchlistChangeBar(outcome: outcome)
        }
        // Fires again when the player pops back to this screen (value-nav) — re-read watch state
        // so Resume · <time> reflects the position the player just recorded.
        .onAppear { Task { await store.reloadWatch() } }
        .fullScreenCover(item: $episodePlayback) { presented in
            PlayerHost(request: presented.request, app: session, backdropSize: "w1280")
        }
        .alert("Remove \u{201C}\(store.item.title)\u{201D}?", isPresented: $confirmingRemove) {
            Button("Remove", role: .destructive) { performRemove() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes it from your Real\u{2011}Debrid account. You can re\u{2011}add it later by searching.")
        }
        .alert("Delete this version?", isPresented: Binding(
            get: { pendingVersionRemoval != nil },
            set: { if !$0 { pendingVersionRemoval = nil } }), presenting: pendingVersionRemoval) { source in
            Button("Delete", role: .destructive) { performVersionRemove(source) }
            Button("Cancel", role: .cancel) { pendingVersionRemoval = nil }
        } message: { source in
            Text(store.versions.count > 1
                 ? "\(source.versionSummary) is deleted from your Real\u{2011}Debrid account. Your other versions of \u{201C}\(store.item.title)\u{201D} stay."
                 : "\(source.versionSummary) is the only version you have, so \u{201C}\(store.item.title)\u{201D} leaves your library.")
        }
        .alert("Couldn\u{2019}t Remove", isPresented: Binding(
            get: { removeError != nil }, set: { if !$0 { removeError = nil } })) {
            Button("OK", role: .cancel) { removeError = nil }
        } message: {
            Text(removeError ?? "")
        }
        .alert("Couldn\u{2019}t Download", isPresented: Binding(
            get: { episodeError != nil }, set: { if !$0 { episodeError = nil } })) {
            Button("OK", role: .cancel) { episodeError = nil }
        } message: {
            Text(episodeError ?? "")
        }
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

    /// Delete ONE version from Real-Debrid. The last one takes the whole title with it (that's what
    /// `LibraryService.removeVersion` does), so the screen closes in that case; otherwise it stays
    /// open with that row gone.
    private func performVersionRemove(_ source: MediaSource) {
        guard let library = session.libraryStore else { return }
        pendingVersionRemoval = nil
        Task {
            switch await library.removeVersionReportingFailure(store.item, source: source) {
            case let .removed(wasLast):
                if wasLast {
                    dismiss()
                } else {
                    await store.forgetVersion(source)
                }
            case let .failed(message):
                removeError = message
            }
        }
    }

    /// A not-downloaded episode was selected → find it, add it, play it.
    private func downloadAndPlayEpisode(_ row: DetailStore.EpisodeRowInfo) {
        playEpisode(season: row.season, number: row.number, id: row.id)
    }

    /// Acquire and play one episode, addressed by number so it works for a show you have not added
    /// at all. Falls through to a tracked download when Real-Debrid has nothing instant.
    private func playEpisode(season: Int, number: Int, id: String) {
        guard let acquirer else { return }
        downloadingEpisodeID = id
        Task {
            let outcome = await acquirer.play(.episode(season: season, number: number))
            downloadingEpisodeID = nil
            switch outcome {
            case let .play(request):
                episodePlayback = EpisodePlayback(request: request)
            case let .failed(message) where !message.isEmpty:
                episodeError = message
            default:
                break
            }
        }
    }
}
