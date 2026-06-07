import DebridCore
import DebridUI
import SwiftUI
import WebKit

/// A "Trailer" button that resolves the title's YouTube key on appear and presents the in-app
/// trailer player. Renders nothing until a key resolves (no trailer → no button).
struct TrailerButton: View {
    let tmdbID: Int?
    let kind: MediaKind
    @Environment(AppSession.self) private var session
    @State private var key: String?
    @State private var showing = false

    var body: some View {
        Group {
            if let key {
                Button { showing = true } label: {
                    Label("Trailer", systemImage: "play.rectangle.fill")
                }
                .buttonStyle(GhostButtonStyle())
                .sheet(isPresented: $showing) { TrailerView(youTubeKey: key) }
            } else {
                // A real zero-size host so `.task` actually runs: SwiftUI distributes `.task` to a
                // Group's children, and an empty Group (key == nil) has none — so without this the
                // task never fires, the key never resolves, and the button never appears.
                Color.clear.frame(width: 0, height: 0)
            }
        }
        .task(id: tmdbID) {
            guard let tmdbID else { return }
            key = await session.trailers?.trailerKey(tmdbID: tmdbID, kind: kind)
        }
    }
}

/// In-app YouTube trailer player (iOS/iPadOS has WebKit). Presented as a sheet.
struct TrailerView: View {
    let youTubeKey: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            YouTubeEmbed(key: youTubeKey)
                .ignoresSafeArea(edges: .bottom)
                .background(Color.black)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") { dismiss() }.tint(Theme.Palette.gold)
                    }
                }
        }
        .preferredColorScheme(.dark)
    }
}

private struct YouTubeEmbed: UIViewRepresentable {
    let key: String
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = .black
        if let url = URL(string: "https://www.youtube.com/embed/\(key)?autoplay=1&playsinline=1&rel=0") {
            web.load(URLRequest(url: url))
        }
        return web
    }
    func updateUIView(_ web: WKWebView, context: Context) {}
}
