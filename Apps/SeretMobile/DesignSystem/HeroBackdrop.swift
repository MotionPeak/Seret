import SwiftUI

/// Backdrop image fading into the canvas, with an overlay (title/buttons) at bottom-leading.
struct HeroBackdrop<Overlay: View>: View {
    let imageURL: URL?
    var height: CGFloat = 220
    @ViewBuilder var overlay: Overlay
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: imageURL) { phase in
                if case .success(let image) = phase { image.resizable().scaledToFill() }
                else { Theme.Palette.surface1 }
            }
            .frame(height: height).frame(maxWidth: .infinity).clipped()
            LinearGradient(
                stops: [.init(color: .clear, location: 0.0),
                        .init(color: Theme.Palette.canvas.opacity(0.6), location: 0.55),
                        .init(color: Theme.Palette.canvas, location: 1.0)],
                startPoint: .top, endPoint: .bottom)
            .frame(height: height)
            overlay.padding(Theme.Space.lg)
        }
        .frame(height: height)
    }
}
