import DebridCore
import DebridUI
import SwiftUI

/// The sign-in backdrop: a tilted wall of popular posters drifting slowly behind a dark veil (approved
/// mockup 6). Before sign-in there is no library, so it shows TMDB's popular films and shows; offline
/// it is simply the gold-glow canvas.
struct PosterMosaic: View {
    let urls: [URL]
    @State private var drift = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 10)
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(Array(urls.enumerated()), id: \.offset) { _, url in
                    // A fixed 2:3 cell the image fills and is clipped to, whatever the artwork's shape.
                    Color.clear
                        .aspectRatio(2 / 3, contentMode: .fit)
                        .overlay(RemoteImage(url: url))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .frame(width: geo.size.width * 1.4)
            .rotationEffect(.degrees(-9))
            .offset(x: drift ? -geo.size.width * 0.26 : -geo.size.width * 0.18,
                    y: drift ? -geo.size.height * 0.42 : -geo.size.height * 0.30)
            .brightness(-0.08)
            .saturation(0.85)
            .opacity(0.36)
        }
        .overlay(
            RadialGradient(colors: [Theme.Palette.canvas.opacity(0.35), Theme.Palette.canvas.opacity(0.94)],
                           center: .init(x: 0.5, y: 0.45), startRadius: 0, endRadius: 700)
        )
        .background(Theme.Palette.canvas)
        .clipped()
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 70).repeatForever(autoreverses: true)) { drift = true }
        }
    }

    /// Popular posters from TMDB (no account needed). Empty when offline or keyless.
    static func loadPopularPosters() async -> [URL] {
        let tmdb = TMDBClient(apiKey: Secrets.tmdbAPIKey)
        let movies = (try? await tmdb.popularMovies()) ?? []
        let shows = (try? await tmdb.popularTV()) ?? []
        let paths = (movies + shows).compactMap(\.posterPath)
        let urls = paths.compactMap { TMDBClient.imageURL(path: $0, size: "w185") }
        return urls.isEmpty ? [] : Array(repeating: urls, count: 3).flatMap { $0 }.prefix(90).map { $0 }
    }
}
