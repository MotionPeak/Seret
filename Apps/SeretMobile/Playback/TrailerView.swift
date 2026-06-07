import AVKit
import DebridCore
import DebridUI
import SwiftUI

/// A "Trailer" button: resolves the title's trailer to a playable stream on appear and plays it
/// full-screen in-app (AVPlayer). Falls back to opening YouTube if extraction fails. Renders
/// nothing until there's something to offer.
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
                .buttonStyle(GhostButtonStyle())
                .fullScreenCover(isPresented: $showing) { cover(model) }
            } else {
                // A real zero-size host so `.task` actually runs (an empty Group has no child to
                // host it — the bug that hid the button before).
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

    /// Offer the button when we can either play in-app (stream URL) or at least deep-link (key).
    private func canOffer(_ m: TrailerModel) -> Bool {
        m.streamURL != nil || m.youTubeKey != nil
    }

    @ViewBuilder private func cover(_ m: TrailerModel) -> some View {
        if let url = m.streamURL {
            FullScreenTrailer(url: url)
        } else {
            // Extraction failed but we have a key → bounce to YouTube, then dismiss.
            Color.black.ignoresSafeArea()
                .onAppear {
                    if let key = m.youTubeKey,
                       let url = URL(string: "https://www.youtube.com/watch?v=\(key)") {
                        UIApplication.shared.open(url)
                    }
                    showing = false
                }
        }
    }
}
