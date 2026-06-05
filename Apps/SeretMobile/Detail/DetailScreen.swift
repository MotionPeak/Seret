import DebridCore
import DebridUI
import SwiftUI

/// Owns the per-title `DetailStore`, dispatches movie vs. show, and registers the player
/// route (a placeholder until 8c's MobileVLCKit player lands).
struct DetailScreen: View {
    @State private var store: DetailStore

    init(item: MediaItem, details: MediaDetailsProviding, watch: WatchProgressProviding?) {
        _store = State(initialValue: DetailStore(item: item, details: details, watch: watch))
    }

    var body: some View {
        Group {
            switch store.item.kind {
            case .movie: MovieDetail(store: store)
            case .show:  ShowDetail(store: store)
            }
        }
        .task { await store.load() }
        .navigationDestination(for: PlaybackRequest.self) { PlayerPlaceholder(request: $0) }
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
            .init(color: .black.opacity(0.75), location: 0.55),
            .init(color: .black, location: 1.0),
        ], startPoint: .top, endPoint: .bottom))
        .ignoresSafeArea()
    }
}

/// Quality / source / codec chips for a parsed release (mirrors the tvOS `QualityChips`, touch-styled).
struct QualityChip: View {
    let parsed: ParsedRelease
    private var chips: [String] {
        [parsed.resolution, parsed.source, parsed.videoCodec, parsed.audioCodec].compactMap { $0 }
    }
    var body: some View {
        HStack(spacing: 6) {
            ForEach(chips, id: \.self) { c in
                Text(c).font(.caption2.weight(.semibold))
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(.white.opacity(0.15), in: Capsule())
            }
        }
    }
}

/// Placeholder player target until 8c wires the `MobileVLCKit` touch player.
struct PlayerPlaceholder: View {
    let request: PlaybackRequest
    var body: some View {
        ContentUnavailableView {
            Label(request.label, systemImage: "play.rectangle.fill")
        } description: {
            Text("The player lands in 8c (MobileVLCKit).")
        }
        .navigationTitle("Play")
        .navigationBarTitleDisplayMode(.inline)
    }
}
