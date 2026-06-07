import DebridCore
import DebridUI
import SwiftUI

/// The detail hero background: the TMDB backdrop, which ~4s after the page opens cross-fades to a
/// muted, looping trailer (when autoplay is on and a stream resolves). Ambient only — controls
/// can't live here (a `.background` view doesn't receive touches under the scroll view), so sound
/// comes from the full-screen Trailer button. Tears down on disappear.
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
            DetailBackdrop(path: backdropPath, posterFallback: posterFallback)
            if showVideo, let url = model?.streamURL {
                InlineMutedTrailer(url: url, muted: .constant(true))
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
        .task(id: tmdbID) {
            guard let tmdbID, model == nil, let m = session.makeTrailerModel() else { return }
            model = m
            // Run the minimum on-backdrop delay CONCURRENTLY with resolution so the trailer appears
            // at ~4s — not 4s AFTER extraction finishes (which felt like ~15s).
            async let delayDone: () = Task.sleep(for: .seconds(4))
            await m.prepare(tmdbID: tmdbID, kind: kind)
            try? await delayDone
            guard m.autoplayAllowed, !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.6)) { showVideo = true }
        }
        .onDisappear { showVideo = false }
    }
}
