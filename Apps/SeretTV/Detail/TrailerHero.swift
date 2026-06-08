import DebridCore
import DebridUI
import SwiftUI

/// Contained hero banner at the top of a tvOS Detail page: the TMDB backdrop, which ~4s after the
/// page opens cross-fades to a muted, looping trailer (when autoplay is on and a stream resolves).
/// The bottom edge fades into the solid canvas so the title/overview below stay legible. No tap on
/// tvOS — the focusable Trailer button in the actions row plays the trailer full-screen with sound.
struct TrailerHero: View {
    let tmdbID: Int?
    let kind: MediaKind
    let backdropPath: String?
    let posterFallback: String?
    /// Published up once resolved so the detail can present "swipe up" full-screen playback.
    @Binding var resolvedURL: URL?

    @Environment(AppSession.self) private var session
    @State private var model: TrailerModel?
    @State private var showVideo = false

    var body: some View {
        // Fixed-size base so the aspect-fill backdrop/trailer (clipped overlays) can't dictate and
        // overflow the banner's width — which would push the content below off-screen.
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 620)
            .overlay { backdropImage }
            .overlay {
                if showVideo, let url = model?.streamURL {
                    InlineMutedTrailer(url: url).transition(.opacity)
                }
            }
            .clipped()
            .overlay(scrim)
            .task(id: tmdbID) { await prepare() }
            .onDisappear { showVideo = false }
    }

    private var backdropImage: some View {
        Group {
            if let url = TMDBClient.imageURL(path: backdropPath, size: "w1280")
                ?? TMDBClient.imageURL(path: posterFallback, size: "w780") {
                AsyncImage(url: url, transaction: Transaction(animation: Theme.Anim.imageFade)) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill).transition(.opacity)
                    } else {
                        Theme.Palette.surface1
                    }
                }
            } else {
                LinearGradient(colors: [Theme.Palette.surface1, .black], startPoint: .top, endPoint: .bottom)
            }
        }
    }

    private var scrim: some View {
        LinearGradient(stops: [
            .init(color: .black.opacity(0.35), location: 0.0),
            .init(color: .clear, location: 0.30),
            .init(color: Theme.Palette.canvas.opacity(0.7), location: 0.80),
            .init(color: Theme.Palette.canvas, location: 1.0),
        ], startPoint: .top, endPoint: .bottom)
    }

    private func prepare() async {
        guard let tmdbID, model == nil, let m = session.makeTrailerModel() else { return }
        model = m
        async let delay: () = Task.sleep(for: .seconds(4))
        await m.prepare(tmdbID: tmdbID, kind: kind)
        resolvedURL = m.streamURL          // publish up for swipe-up full-screen
        try? await delay
        guard m.autoplayAllowed, !Task.isCancelled else { return }
        withAnimation(.easeInOut(duration: 0.6)) { showVideo = true }
    }
}
