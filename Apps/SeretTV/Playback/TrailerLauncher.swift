import DebridCore
import DebridUI
import SwiftUI
import UIKit

/// A "Trailer" button for tvOS. tvOS has no WebKit and no Safari, so it deep-links to the
/// YouTube app via `youtube://`. Renders nothing unless a trailer key resolves AND the YouTube
/// app can open it (so the user never taps a dead button).
struct TrailerButton: View {
    let tmdbID: Int?
    let kind: MediaKind
    @Environment(AppSession.self) private var session
    @State private var key: String?

    var body: some View {
        Group {
            if let key, let url = Self.youTubeURL(for: key) {
                Button { UIApplication.shared.open(url) } label: {
                    Label("Trailer", systemImage: "play.rectangle.fill")
                }
            }
        }
        .task(id: tmdbID) {
            guard let tmdbID else { return }
            key = await session.trailers?.trailerKey(tmdbID: tmdbID, kind: kind)
        }
    }

    /// The `youtube://` deep link if the YouTube app is installed (whitelisted in
    /// `LSApplicationQueriesSchemes`), else nil.
    static func youTubeURL(for key: String) -> URL? {
        for scheme in ["youtube://watch?v=\(key)", "vnd.youtube://\(key)"] {
            if let url = URL(string: scheme), UIApplication.shared.canOpenURL(url) { return url }
        }
        return nil
    }
}
