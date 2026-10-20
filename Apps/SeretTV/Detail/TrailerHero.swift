import DebridCore
import DebridUI
import SwiftUI

/// The title page's background: the title's backdrop as a Plex "ultrablur" (a blurred wash over
/// the whole screen, the sharp art in the top-trailing 70% × 76%), and ~4s after the page opens a
/// muted, looping trailer cross-fading into the sharp art's place (when autoplay is on and a stream
/// resolves). The trailer dissolves into the wash exactly as the still does, and sits under the
/// same legibility shade, so the title, overview and buttons over it always read.
///
/// It is the page's BACKGROUND, not a banner at the top of the scroll: the title page is the hero,
/// and the art stays put while the rails scroll over it. No tap on tvOS — the focusable Trailer
/// action plays the trailer full-screen with sound.
struct TrailerHero: View {
    let tmdbID: Int?
    let kind: MediaKind
    /// The backdrop to show; nil draws the plain canvas.
    let backdropPath: String?
    /// Published up once resolved so the page can offer full-screen playback.
    @Binding var resolvedURL: URL?
    /// True while something covers the page (the full-screen trailer) or the viewer has scrolled
    /// down to the rails. A cover does not make the page disappear, so the muted loop kept
    /// decoding underneath it: two video streams at once on an Apple TV, one nobody could see.
    var paused = false
    /// Darkens the art once the viewer has scrolled past the title: the rails then run the full
    /// width of the screen, and over bright sharp art their titles and captions lost contrast.
    var receded = false

    @Environment(AppSession.self) private var session
    @State private var model: TrailerModel?
    @State private var showVideo = false

    var body: some View {
        ZStack {
            UltrablurBackdrop(backdropPath: backdropPath,
                              artOverlay: AnyView(TrailerLayer(url: showVideo && !paused
                                                                    ? model?.streamURL : nil)))
            Theme.Palette.shadeInk
                .opacity(receded ? 0.55 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .animation(Theme.Anim.backdrop, value: receded)
        }
        .accessibilityHidden(true)
        .task(id: tmdbID) { await prepare() }
        .onDisappear { showVideo = false }
    }

    private func prepare() async {
        guard let tmdbID, model == nil, let m = session.makeTrailerModel() else { return }
        model = m
        async let delay: () = Task.sleep(for: .seconds(4))
        await m.prepare(tmdbID: tmdbID, kind: kind)
        resolvedURL = m.streamURL          // publish up for full-screen playback
        try? await delay
        guard m.autoplayAllowed, !Task.isCancelled else { return }
        withAnimation(Theme.Anim.backdrop) { showVideo = true }
    }
}

/// The muted loop, or nothing. One stable container whose CONTENT comes and goes, so the
/// backdrop's overlay keeps its identity while the video starts and stops.
private struct TrailerLayer: View {
    let url: URL?

    var body: some View {
        ZStack {
            if let url {
                InlineMutedTrailer(url: url).transition(.opacity)
            }
        }
        .animation(Theme.Anim.backdrop, value: url)
    }
}
