import DebridCore
import DebridUI
import SwiftUI

/// Full-screen backdrop (or poster fallback) with a darkening scrim, behind a Detail screen.
struct BackdropBackground: View {
    let path: String?            // TMDB backdrop path
    let posterFallback: String?

    var body: some View {
        image
            .overlay(scrim)
            .ignoresSafeArea()
    }

    @ViewBuilder private var image: some View {
        if let url = TMDBClient.imageURL(path: path, size: "w1280")
            ?? TMDBClient.imageURL(path: posterFallback, size: "w780") {
            AsyncImage(url: url, transaction: Transaction(animation: Theme.Anim.imageFade)) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill).transition(.opacity)
                } else {
                    ZStack { Color.black; ProgressView().tint(Theme.Palette.gold) }
                }
            }
        } else {
            LinearGradient(colors: [.gray.opacity(0.3), .black], startPoint: .top, endPoint: .bottom)
        }
    }

    private var scrim: some View {
        LinearGradient(stops: [
            .init(color: .black.opacity(0.95), location: 0.0),
            .init(color: .black.opacity(0.45), location: 0.5),
            .init(color: .black.opacity(0.85), location: 1.0),
        ], startPoint: .leading, endPoint: .trailing)
    }
}
