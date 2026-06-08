import DebridCore
import DebridUI
import SwiftUI

struct DetailView: View {
    @State private var store: DetailStore
    @State private var confirmingRemove = false
    @State private var removeError: String?
    @State private var downloadingEpisodeID: String?
    @State private var episodePlayback: EpisodePlayback?
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    /// Wraps a just-downloaded episode's request for `.fullScreenCover(item:)` (downloaded episodes
    /// play via the value-nav link in `EpisodeRow`; this covers the download-then-play path).
    private struct EpisodePlayback: Identifiable { let id = UUID(); let request: PlaybackRequest }

    init(item: MediaItem, details: MediaDetailsProviding, watch: WatchProgressProviding?,
         profileID: String? = nil, ratings: RatingsProviding? = nil) {
        _store = State(initialValue: DetailStore(item: item, details: details, watch: watch,
                                                 profileID: profileID, ratings: ratings))
    }

    var body: some View {
        Group {
            switch store.item.kind {
            case .movie: MovieDetailView(store: store, onRemove: { confirmingRemove = true })
            case .show:  ShowDetailView(
                store: store, onRemove: { confirmingRemove = true },
                makeSeasonDownload: { imdb, season, lang in
                    session.makeSeasonDownload(imdbID: imdb, season: season, originalLanguage: lang)
                },
                onSeasonAdded: { session.libraryStore?.retry() },
                onDownloadEpisode: downloadAndPlayEpisode,
                downloadingEpisodeID: downloadingEpisodeID)
            }
        }
        .task { await store.load() }
        .fullScreenCover(item: $episodePlayback) { presented in
            let engine = VLCKitVideoPlayerEngine(preferences: session.subtitleSettings.preferences)
            if let model = session.makePlayer(for: presented.request, engine: engine) {
                PlayerView(model: model, engine: engine,
                           backdropURL: TMDBClient.imageURL(path: presented.request.item.backdropPath, size: "w1280"))
            } else {
                Text("Unable to start playback.").font(.title2)
            }
        }
        .alert("Remove \u{201C}\(store.item.title)\u{201D}?", isPresented: $confirmingRemove) {
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

    /// A not-downloaded episode was selected → add the best cached version, refresh the library,
    /// and present the player.
    private func downloadAndPlayEpisode(_ row: DetailStore.EpisodeRowInfo) {
        guard let imdb = store.imdbID,
              let add = session.makeAddStore(imdbID: imdb,
                                             kind: .series(season: row.season, episode: row.number),
                                             originalLanguage: store.originalLanguage) else { return }
        downloadingEpisodeID = row.id
        Task {
            await add.addBest()
            downloadingEpisodeID = nil
            if case let .added(info) = add.state,
               let req = store.playRequest(forAdded: info, season: row.season, number: row.number) {
                session.libraryStore?.retry()
                episodePlayback = EpisodePlayback(request: req)
            }
        }
    }
}
