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
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    init(item: MediaItem, details: MediaDetailsProviding, watch: WatchProgressProviding?,
         profileID: String? = nil, ratings: RatingsProviding? = nil) {
        _store = State(initialValue: DetailStore(item: item, details: details, watch: watch,
                                                 profileID: profileID, ratings: ratings))
    }

    var body: some View {
        NavigationStack {
            Group {
                switch store.item.kind {
                case .movie: MovieDetail(store: store, onPlay: present,
                                        onRemoveVersion: { src in
                                            Task { await session.libraryStore?.removeVersion(store.item, source: src) }
                                        })
                case .show:  ShowDetail(
                                store: store, onPlay: present,
                                makeSeasonDownload: { imdb, season, lang in
                                    session.makeSeasonDownload(imdbID: imdb, season: season, originalLanguage: lang)
                                },
                                makeEpisodeDownload: { imdb, season, episode, lang in
                                    session.makeAddStore(imdbID: imdb, kind: .series(season: season, episode: episode),
                                                         originalLanguage: lang)
                                },
                                onSeasonAdded: { session.libraryStore?.retry() })
                }
            }
            .task { await store.load() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "chevron.down").font(.headline) }
                        .tint(Theme.Palette.gold)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
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
        .fullScreenCover(item: $playback) { presented in
            let engine = VLCKitVideoPlayerEngine(preferences: session.subtitleSettings.preferences)
            if let model = session.makePlayer(for: presented.request, engine: engine) {
                PlayerView(model: model, engine: engine,
                           backdropURL: TMDBClient.imageURL(path: presented.request.item.backdropPath, size: "w1280"),
                           onExit: { playback = nil })
            } else {
                PlayerPlaceholder(request: presented.request)
            }
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
                AsyncImage(url: url) { $0.resizable().aspectRatio(contentMode: .fill) }
                    placeholder: { Color.black }
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
