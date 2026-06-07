import AVKit
import DebridCore
import DebridUI
import SwiftUI
import UIKit

/// A "Trailer" button for tvOS: resolves the title's trailer to a playable stream on appear and
/// plays it full-screen in-app (AVPlayer). Falls back to opening the YouTube app if extraction
/// fails. Renders nothing until there's something to offer.
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

    private func canOffer(_ m: TrailerModel) -> Bool {
        m.streamURL != nil || m.youTubeKey != nil
    }

    @ViewBuilder private func cover(_ m: TrailerModel) -> some View {
        if let url = m.streamURL {
            FullScreenTrailer(url: url)
        } else {
            // Extraction failed but we have a key → open the YouTube app, then dismiss.
            Color.black.ignoresSafeArea()
                .onAppear {
                    if let key = m.youTubeKey, let url = Self.youTubeURL(for: key) {
                        UIApplication.shared.open(url)
                    }
                    showing = false
                }
        }
    }

    /// The `youtube://` deep link if the YouTube app is installed, else nil.
    static func youTubeURL(for key: String) -> URL? {
        for scheme in ["youtube://watch?v=\(key)", "vnd.youtube://\(key)"] {
            if let url = URL(string: scheme), UIApplication.shared.canOpenURL(url) { return url }
        }
        return nil
    }
}
