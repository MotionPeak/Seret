import DebridCore
import DebridUI
import SwiftUI

/// The detail hero background: the TMDB backdrop, which ~4s after the page opens cross-fades to a
/// muted, looping trailer (when autoplay is on and a stream resolves). Ambient only — it's a
/// `.background` view and can't take touches, so it publishes the resolved stream URL up via
/// `resolvedURL` and the detail's foreground hero handles tap-to-expand. Tears down on disappear.
struct AutoplayBackdrop: View {
    let tmdbID: Int?
    let kind: MediaKind
    let backdropPath: String?
    let posterFallback: String?
    /// Set to the playable stream URL once resolved (whether or not auto-play is on) so the detail
    /// can offer "tap to watch full-screen". Nil while resolving / unavailable.
    @Binding var resolvedURL: URL?

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
            // Min on-backdrop delay runs CONCURRENTLY with resolution → appears at ~4s, not 4s
            // AFTER extraction (which felt like ~15s).
            async let delayDone: () = Task.sleep(for: .seconds(4))
            await m.prepare(tmdbID: tmdbID, kind: kind)
            resolvedURL = m.streamURL            // publish up for tap-to-expand (even if autoplay off)
            try? await delayDone
            guard m.autoplayAllowed, !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.6)) { showVideo = true }
        }
        .onDisappear { showVideo = false }
    }
}
