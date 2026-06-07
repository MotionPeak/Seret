import DebridCore
import DebridUI
import SwiftUI

/// Contained hero banner at the top of a Detail page: the TMDB backdrop, which ~4s after the page
/// opens cross-fades to a muted, looping trailer (when autoplay is on and a stream resolves). The
/// bottom edge fades into the solid app canvas so the title/overview below stay perfectly legible.
/// While the trailer plays it shows a speaker (unmute) and an expand control; tapping the banner
/// (or the expand control) opens the trailer full-screen with sound. Self-contained.
struct TrailerHero: View {
    let tmdbID: Int?
    let kind: MediaKind
    let backdropPath: String?
    let posterFallback: String?

    @Environment(AppSession.self) private var session
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var model: TrailerModel?
    @State private var showVideo = false
    @State private var muted = true
    @State private var expand = false

    private var heroHeight: CGFloat { sizeClass == .regular ? 380 : 260 }

    var body: some View {
        // A fixed-size base (Color.clear) establishes the banner's width/height; the backdrop and
        // trailer are clipped OVERLAYS so their aspect-fill can't dictate (and overflow) the width.
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: heroHeight)
            .overlay { backdropImage }
            .overlay {
                if showVideo, let url = model?.streamURL {
                    InlineMutedTrailer(url: url, muted: $muted).transition(.opacity)
                }
            }
            .clipped()
            .overlay(scrim)
        .overlay(alignment: .bottomTrailing) { if showVideo { controls } }
        .contentShape(Rectangle())
        .onTapGesture { if model?.streamURL != nil { expand = true } }
        .task(id: tmdbID) { await prepare() }
        .onDisappear { showVideo = false }
        .fullScreenCover(isPresented: $expand) {
            if let u = model?.streamURL { FullScreenTrailer(url: u) }
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            controlButton(muted ? "speaker.slash.fill" : "speaker.wave.2.fill") { muted.toggle() }
            controlButton("arrow.up.left.and.arrow.down.right") { expand = true }
        }
        .padding(.trailing, Theme.Space.lg)
        .padding(.bottom, Theme.Space.md)
    }

    private func controlButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.subheadline.weight(.bold))
                .frame(width: 38, height: 38)
                .background(.black.opacity(0.5), in: Circle())
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
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

    private func prepare() async {
        guard let tmdbID, model == nil, let m = session.makeTrailerModel() else { return }
        model = m
        async let delay: () = Task.sleep(for: .seconds(4))
        await m.prepare(tmdbID: tmdbID, kind: kind)
        try? await delay
        guard m.autoplayAllowed, !Task.isCancelled else { return }
        withAnimation(.easeInOut(duration: 0.6)) { showVideo = true }
    }
}
