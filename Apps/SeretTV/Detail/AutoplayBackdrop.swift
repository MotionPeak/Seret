import DebridCore
import DebridUI
import SwiftUI

/// The detail hero background (tvOS): the TMDB backdrop, which after ~4s cross-fades to a muted,
/// looping trailer (when autoplay is on and a stream resolves). Tears down on disappear. No inline
/// unmute control on tvOS — the focusable Trailer button plays full-screen with sound.
struct AutoplayBackdrop: View {
    let tmdbID: Int?
    let kind: MediaKind
    let backdropPath: String?
    let posterFallback: String?

    @Environment(AppSession.self) private var session
    @State private var model: TrailerModel?
    @State private var showVideo = false

    var body: some View {
        ZStack {
            BackdropBackground(path: backdropPath, posterFallback: posterFallback)
            if showVideo, let url = model?.streamURL {
                InlineMutedTrailer(url: url)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
        .task(id: tmdbID) {
            guard let tmdbID, model == nil else { return }
            let m = session.makeTrailerModel()
            model = m
            await m?.prepare(tmdbID: tmdbID, kind: kind)
            guard let m, m.autoplayAllowed else { return }
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.6)) { showVideo = true }
            }
        }
        .onDisappear { showVideo = false }
    }
}
