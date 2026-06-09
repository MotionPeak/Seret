import AVKit
import DebridCore
import DebridUI
import SwiftUI
import UIKit

/// A "Trailer" button for tvOS: resolves the title's trailer to a playable stream on appear and
/// plays it full-screen in-app (AVPlayer). The button appears ONLY once the in-app stream is
/// ready, so pressing it always plays. If extraction fails, no button is shown — we never
/// deep-link to the YouTube app (on tvOS that just dumps you into YouTube and does nothing).
struct TrailerButton: View {
    let tmdbID: Int?
    let kind: MediaKind
    @Environment(AppSession.self) private var session
    @State private var model: TrailerModel?
    @State private var showing = false

    var body: some View {
        Group {
            if let model, canOffer(model) {
                Button { showing = true } label: {
                    Label("Trailer", systemImage: "play.rectangle.fill")
                }
                .fullScreenCover(isPresented: $showing) { cover(model) }
            } else {
                // A real zero-size host so `.task` actually runs (an empty Group has no child).
                Color.clear.frame(width: 0, height: 0)
            }
        }
        .task(id: tmdbID) {
            guard let tmdbID, model == nil else { return }
            let m = session.makeTrailerModel()
            model = m
            await m?.prepare(tmdbID: tmdbID, kind: kind)
        }
    }

    /// Offer the button only when the in-app stream is actually ready — so a press always plays
    /// (never a half-resolved state that bailed to the YouTube app).
    private func canOffer(_ m: TrailerModel) -> Bool {
        m.streamURL != nil
    }

    @ViewBuilder private func cover(_ m: TrailerModel) -> some View {
        if let url = m.streamURL {
            FullScreenTrailer(url: url)
        } else {
            // canOffer gates on a ready stream, so this shouldn't happen — but never deep-link to
            // YouTube (dead end on tvOS); just dismiss.
            Color.black.ignoresSafeArea().onAppear { showing = false }
        }
    }
}
