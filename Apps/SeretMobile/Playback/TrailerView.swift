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
        web.scrollView.isScrollEnabled = false
        // Embed via an <iframe> inside an HTML page served from a youtube.com baseURL — NOT by
        // loading the /embed/ URL as the top-level document. YouTube's player rejects a top-level
        // /embed/ load with "Error 153: player configuration error" because it has no valid
        // embedding origin; an iframe with a youtube.com baseURL gives it one.
        let html = """
        <!DOCTYPE html><html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
        <style>html,body{margin:0;padding:0;height:100%;background:#000;overflow:hidden}
        .wrap{position:absolute;inset:0}iframe{width:100%;height:100%;border:0}</style>
        </head><body><div class="wrap">
        <iframe src="https://www.youtube.com/embed/\(key)?playsinline=1&autoplay=1&rel=0&modestbranding=1"
          allow="autoplay; encrypted-media; picture-in-picture" allowfullscreen></iframe>
        </div></body></html>
        """
        web.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))
        return web
    }
    func updateUIView(_ web: WKWebView, context: Context) {}
}
