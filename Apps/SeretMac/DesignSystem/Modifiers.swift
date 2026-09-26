import SwiftUI

extension View {
    /// Soft gold halo for active and interactive elements.
    func goldGlow(_ radius: CGFloat = 16, opacity: Double = 0.45) -> some View {
        shadow(color: Theme.Palette.gold.opacity(opacity), radius: radius)
    }
}

/// The Gold Glass canvas: near-black with a faint gold glow from the top right. Put behind screens.
struct CanvasBackground: View {
    var body: some View {
        ZStack {
            Theme.Palette.canvas
            Theme.Palette.canvasGlow
        }
        .ignoresSafeArea()
    }
}
