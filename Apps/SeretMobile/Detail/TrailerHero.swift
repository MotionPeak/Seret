import DebridCore
import DebridUI
import SwiftUI

/// Contained hero banner at the top of a Detail page: the TMDB backdrop, which ~4s after the page
/// opens cross-fades to a muted, looping trailer (when autoplay is on and a stream resolves). The
/// bottom edge fades into the solid app canvas so the title/overview below stay perfectly legible.
/// Tap the banner to watch the trailer full-screen with sound. Self-contained (owns the model,
/// timing, and full-screen presentation).
struct TrailerHero: View {
    let tmdbID: Int?
    let kind: MediaKind
    let backdropPath: String?
    let posterFallback: String?

    @Environment(AppSession.self) private var session
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var model: TrailerModel?
    @State private var showVideo = false
    @State private var expand = false

    private var heroHeight: CGFloat { sizeClass == .regular ? 380 : 260 }

    var body: some View {
        ZStack {
            backdropImage
            if showVideo, let url = model?.streamURL {
                InlineMutedTrailer(url: url, muted: .constant(true)).transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: heroHeight)
        .clipped()
        .overlay(scrim)
        .overlay(alignment: .bottomTrailing) { if showVideo { expandHint } }
        .contentShape(Rectangle())
        .onTapGesture { if model?.streamURL != nil { expand = true } }
        .task(id: tmdbID) { await prepare() }
        .onDisappear { showVideo = false }
        .fullScreenCover(isPresented: $expand) {
            if let u = model?.streamURL { FullScreenTrailer(url: u) }
        }
    }

    private var backdropImage: some View {
        Group {
            if let url = TMDBClient.imageURL(path: backdropPath, size: "w1280")
                ?? TMDBClient.imageURL(path: posterFallback, size: "w780") {
                AsyncImage(url: url) { $0.resizable().aspectRatio(contentMode: .fill) }
                    placeholder: { Theme.Palette.surface1 }
            } else {
                LinearGradient(colors: [Theme.Palette.surface1, .black], startPoint: .top, endPoint: .bottom)
            }
        }
    }

    /// Top scrim under the (transparent) nav bar + bottom fade into the canvas content area.
    private var scrim: some View {
        LinearGradient(stops: [
            .init(color: .black.opacity(0.45), location: 0.0),
            .init(color: .clear, location: 0.28),
            .init(color: Theme.Palette.canvas.opacity(0.65), location: 0.82),
            .init(color: Theme.Palette.canvas, location: 1.0),
        ], startPoint: .top, endPoint: .bottom)
    }

    private var expandHint: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.caption.weight(.bold))
            .padding(9)
            .background(.black.opacity(0.45), in: Circle())
            .foregroundStyle(.white)
            .padding(12)
    }

    private func prepare() async {
        guard let tmdbID, model == nil, let m = session.makeTrailerModel() else { return }
        model = m
        // Min on-backdrop delay runs CONCURRENTLY with resolution → appears at ~4s.
        async let delay: () = Task.sleep(for: .seconds(4))
        await m.prepare(tmdbID: tmdbID, kind: kind)
        try? await delay
        guard m.autoplayAllowed, !Task.isCancelled else { return }
        withAnimation(.easeInOut(duration: 0.6)) { showVideo = true }
    }
}
