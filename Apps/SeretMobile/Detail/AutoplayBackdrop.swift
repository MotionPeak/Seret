import DebridCore
import DebridUI
import SwiftUI

/// The detail hero background: the TMDB backdrop, which after ~4s cross-fades to a muted, looping
/// trailer (when autoplay is on and a stream resolves). An unmute button toggles sound. Everything
/// tears down on disappear.
struct AutoplayBackdrop: View {
    let tmdbID: Int?
    let kind: MediaKind
    let backdropPath: String?
    let posterFallback: String?

    @Environment(AppSession.self) private var session
    @State private var model: TrailerModel?
    @State private var showVideo = false
    @State private var muted = true

    var body: some View {
        ZStack {
            DetailBackdrop(path: backdropPath, posterFallback: posterFallback)
            if showVideo, let url = model?.streamURL {
                InlineMutedTrailer(url: url, muted: $muted)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .overlay(alignment: .topTrailing) { muteButton }
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

    private var muteButton: some View {
        Button { muted.toggle() } label: {
            Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.headline)
                .padding(10)
                .background(.black.opacity(0.5), in: Circle())
                .foregroundStyle(.white)
        }
        .padding(.top, 60)
        .padding(.trailing, Theme.Space.lg)
    }
}
