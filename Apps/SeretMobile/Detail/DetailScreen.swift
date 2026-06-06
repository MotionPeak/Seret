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
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    init(item: MediaItem, details: MediaDetailsProviding, watch: WatchProgressProviding?) {
        _store = State(initialValue: DetailStore(item: item, details: details, watch: watch))
    }

    var body: some View {
        NavigationStack {
            Group {
                switch store.item.kind {
                case .movie: MovieDetail(store: store, onPlay: present)
                case .show:  ShowDetail(store: store, onPlay: present)
                }
            }
            .task { await store.load() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "chevron.down").font(.headline) }
                        .tint(Theme.Palette.gold)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .fullScreenCover(item: $playback) { presented in
            let engine = VLCKitVideoPlayerEngine()
            if let model = session.makePlayer(for: presented.request, engine: engine) {
                PlayerView(model: model, engine: engine,
                           backdropURL: TMDBClient.imageURL(path: presented.request.item.backdropPath, size: "w1280"))
            } else {
                PlayerPlaceholder(request: presented.request)
            }
        }
    }

    private func present(_ request: PlaybackRequest) {
        playback = PlaybackPresentation(request: request)
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
            ForEach(chips, id: \.self) { QualityChip(text: $0) }
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
